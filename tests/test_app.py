"""
tests/test_app.py
-----------------
Pytest test suite for the ShelfLife Flask application.

Fixtures:
    app    — creates the Flask app pointing at a temporary SQLite DB.
    client — a Flask test client for making HTTP requests.
"""

import sqlite3
from datetime import date, timedelta

import pytest

from app.app import create_app, get_status


# ===========================================================================
# Fixtures
# ===========================================================================

@pytest.fixture()
def app(tmp_path):
    """
    Create the Flask app wired to a temporary database that is thrown away
    after each test, so tests are fully isolated from one another.
    """
    db_file = tmp_path / "test_shelflife.db"
    flask_app = create_app(db_path=str(db_file))
    flask_app.config["TESTING"] = True
    yield flask_app


@pytest.fixture()
def client(app):
    """Return a Flask test client for the app under test."""
    return app.test_client()


# ===========================================================================
# Helper: insert a row directly into the DB (bypasses HTTP layer)
# ===========================================================================

def _insert_item(app, name="Milk", category="Dairy", quantity=1,
                 expiry_date=None, added_on=None):
    """Insert one item into the test database and return its rowid."""
    if expiry_date is None:
        expiry_date = (date.today() + timedelta(days=10)).isoformat()
    if added_on is None:
        added_on = date.today().isoformat()

    conn = sqlite3.connect(app.config["DB_PATH"])
    cur = conn.execute(
        "INSERT INTO items (name, category, quantity, expiry_date, added_on) "
        "VALUES (?, ?, ?, ?, ?)",
        (name, category, quantity, expiry_date, added_on),
    )
    conn.commit()
    rowid = cur.lastrowid
    conn.close()
    return rowid


# ===========================================================================
# Unit tests for the pure helper function get_status()
# ===========================================================================

def test_get_status_expired():
    """A date in the past should return 'expired'."""
    past = date.today() - timedelta(days=1)
    assert get_status(past) == "expired"


def test_get_status_today():
    """Today's expiry date means the item expires today → 'expiring_soon'."""
    assert get_status(date.today()) == "expiring_soon"


def test_get_status_3_days():
    """An item expiring exactly 3 days from now → 'expiring_soon'."""
    three_days = date.today() + timedelta(days=3)
    assert get_status(three_days) == "expiring_soon"


def test_get_status_4_days():
    """An item expiring 4 days from now is still fresh → 'fresh'."""
    four_days = date.today() + timedelta(days=4)
    assert get_status(four_days) == "fresh"


# ===========================================================================
# Integration tests (HTTP layer)
# ===========================================================================

def test_health_endpoint(client):
    """GET /health should return HTTP 200 and JSON {"status": "ok"}."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data == {"status": "ok"}


def test_dashboard_renders(client):
    """GET / should return HTTP 200 and contain 'Dashboard' or 'ShelfLife'."""
    response = client.get("/")
    assert response.status_code == 200
    body = response.data.decode()
    assert "Dashboard" in body or "ShelfLife" in body


def test_expiring_page(client):
    """GET /expiring should return HTTP 200."""
    response = client.get("/expiring")
    assert response.status_code == 200


def test_inventory_page(client):
    """GET /inventory should return HTTP 200."""
    response = client.get("/inventory")
    assert response.status_code == 200


def test_add_item_post(client):
    """
    POST /add with valid form data should insert the item and
    redirect (HTTP 302) to the dashboard.
    """
    response = client.post(
        "/add",
        data={
            "name": "Orange Juice",
            "category": "Beverages",
            "quantity": "3",
            "expiry_date": (date.today() + timedelta(days=7)).isoformat(),
        },
    )
    assert response.status_code == 302
    # Flask redirects to / on success
    assert response.headers["Location"].endswith("/") or "/" in response.headers["Location"]


def test_delete_item(app, client):
    """
    Insert an item directly into the DB, then POST to /inventory/delete/<id>.
    The item should no longer exist in the database afterwards.
    """
    item_id = _insert_item(app, name="Old Cheese")

    # Verify it was inserted
    conn = sqlite3.connect(app.config["DB_PATH"])
    row = conn.execute("SELECT id FROM items WHERE id = ?", (item_id,)).fetchone()
    assert row is not None, "Item should exist before deletion"
    conn.close()

    # Send the DELETE request
    response = client.post(f"/inventory/delete/{item_id}")
    assert response.status_code == 302  # redirect after delete

    # Verify it was removed
    conn = sqlite3.connect(app.config["DB_PATH"])
    row = conn.execute("SELECT id FROM items WHERE id = ?", (item_id,)).fetchone()
    assert row is None, "Item should be gone after deletion"
    conn.close()
