"""
ShelfLife - Pantry and Expiry Tracker
Flask application using the app factory pattern.
"""

import os
import sqlite3
from datetime import date, timedelta
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, g


def get_status(expiry_date, today=None):
    """
    Determine the status of an item based on its expiry date.

    Args:
        expiry_date: A date object representing when the item expires.
        today: Optional date to use as "today" (defaults to date.today()).

    Returns:
        "expired"       if expiry_date < today
        "expiring_soon" if 0 <= (expiry_date - today).days <= 3
        "fresh"         otherwise
    """
    if today is None:
        today = date.today()

    if expiry_date < today:
        return "expired"
    elif (expiry_date - today).days <= 3:
        return "expiring_soon"
    else:
        return "fresh"


def create_app(db_path=None):
    """
    Application factory function.

    Args:
        db_path: Optional path to the SQLite database file.
                 Falls back to DB_PATH env var, then 'data/shelflife.db'.

    Returns:
        A configured Flask application instance.
    """
    app = Flask(__name__)

    # Secret key required for flash messages (session support)
    app.secret_key = os.environ.get("SECRET_KEY", "shelflife-dev-secret-key")

    # Resolve database path: argument > env var > default
    if db_path is None:
        db_path = os.environ.get("DB_PATH", "data/shelflife.db")

    app.config["DB_PATH"] = db_path

    # Ensure the directory containing the database exists
    db_dir = os.path.dirname(db_path)
    if db_dir:
        os.makedirs(db_dir, exist_ok=True)

    # --- Database helpers ---

    def get_db():
        """Open a database connection (one per request, stored on g)."""
        if "db" not in g:
            g.db = sqlite3.connect(
                app.config["DB_PATH"],
                detect_types=sqlite3.PARSE_DECLTYPES | sqlite3.PARSE_COLNAMES,
            )
            g.db.row_factory = sqlite3.Row  # access columns by name
        return g.db

    @app.teardown_appcontext
    def close_db(exception):
        """Close the database connection at the end of a request."""
        db = g.pop("db", None)
        if db is not None:
            db.close()

    def init_db():
        """Create the items table if it does not already exist."""
        with app.app_context():
            db = get_db()
            db.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    name        TEXT    NOT NULL,
                    category    TEXT    NOT NULL,
                    quantity    INTEGER NOT NULL,
                    expiry_date DATE    NOT NULL,
                    added_on    DATE    NOT NULL
                )
            """)
            db.commit()

    # Initialise the database on startup
    init_db()

    # --- Constants ---

    CATEGORIES = ["Dairy", "Vegetables", "Fruits", "Grains", "Snacks", "Beverages", "Other"]

    # --- Routes ---

    @app.route("/")
    def dashboard():
        """
        Dashboard page.
        Shows counts of expired / expiring soon / fresh items
        and a per-category breakdown.
        """
        db = get_db()
        rows = db.execute(
            "SELECT * FROM items ORDER BY expiry_date"
        ).fetchall()

        today = date.today()

        # Tally statuses and categories
        counts = {"expired": 0, "expiring_soon": 0, "fresh": 0}
        category_counts = {}

        for row in rows:
            # expiry_date comes back as a string when detect_types isn't enough
            expiry = row["expiry_date"]
            if isinstance(expiry, str):
                expiry = date.fromisoformat(expiry)

            status = get_status(expiry, today)
            counts[status] += 1

            cat = row["category"]
            category_counts[cat] = category_counts.get(cat, 0) + 1

        return render_template(
            "index.html",
            counts=counts,
            category_counts=category_counts,
            title="Dashboard",
        )

    @app.route("/add", methods=["GET", "POST"])
    def add_item():
        """
        Add a new pantry item.
        GET  — render the form.
        POST — validate and insert, then redirect to dashboard.
        """
        errors = []

        if request.method == "POST":
            name        = request.form.get("name", "").strip()
            category    = request.form.get("category", "").strip()
            quantity_s  = request.form.get("quantity", "").strip()
            expiry_s    = request.form.get("expiry_date", "").strip()

            # --- Validation ---
            if not name:
                errors.append("Name is required.")
            if category not in CATEGORIES:
                errors.append("Please select a valid category.")
            if not quantity_s:
                errors.append("Quantity is required.")
            else:
                try:
                    quantity = int(quantity_s)
                    if quantity < 1:
                        errors.append("Quantity must be at least 1.")
                except ValueError:
                    errors.append("Quantity must be a whole number.")
                    quantity = None
            if not expiry_s:
                errors.append("Expiry date is required.")
            else:
                try:
                    expiry_date = date.fromisoformat(expiry_s)
                except ValueError:
                    errors.append("Expiry date must be in YYYY-MM-DD format.")
                    expiry_date = None

            if not errors:
                db = get_db()
                db.execute(
                    """
                    INSERT INTO items (name, category, quantity, expiry_date, added_on)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (name, category, quantity, expiry_s, date.today().isoformat()),
                )
                db.commit()
                flash(f'"{name}" added to your pantry!', "success")
                return redirect(url_for("dashboard"))

        return render_template(
            "add.html",
            categories=CATEGORIES,
            errors=errors,
            title="Add Item",
        )

    @app.route("/expiring")
    def expiring():
        """
        Expiring items page.
        Shows items that are already expired or will expire within 3 days,
        sorted by expiry_date ascending.
        """
        db = get_db()
        today = date.today()
        cutoff = (today + timedelta(days=3)).isoformat()

        rows = db.execute(
            "SELECT * FROM items WHERE expiry_date <= ? ORDER BY expiry_date",
            (cutoff,),
        ).fetchall()

        # Attach status to each row for template use
        items = []
        for row in rows:
            expiry = row["expiry_date"]
            if isinstance(expiry, str):
                expiry = date.fromisoformat(expiry)
            items.append({
                "id":          row["id"],
                "name":        row["name"],
                "category":    row["category"],
                "quantity":    row["quantity"],
                "expiry_date": expiry,
                "added_on":    row["added_on"],
                "status":      get_status(expiry, today),
            })

        return render_template("expiring.html", items=items, title="Expiring Soon")

    @app.route("/inventory")
    def inventory():
        """
        Full inventory page, sorted by expiry_date.
        Each row has a Delete button.
        """
        db = get_db()
        today = date.today()

        rows = db.execute(
            "SELECT * FROM items ORDER BY expiry_date"
        ).fetchall()

        items = []
        for row in rows:
            expiry = row["expiry_date"]
            if isinstance(expiry, str):
                expiry = date.fromisoformat(expiry)
            items.append({
                "id":          row["id"],
                "name":        row["name"],
                "category":    row["category"],
                "quantity":    row["quantity"],
                "expiry_date": expiry,
                "added_on":    row["added_on"],
                "status":      get_status(expiry, today),
            })

        return render_template("inventory.html", items=items, title="Inventory")

    @app.route("/inventory/delete/<int:item_id>", methods=["POST"])
    def delete_item(item_id):
        """Delete an inventory item by its ID and redirect back to the inventory page."""
        db = get_db()
        db.execute("DELETE FROM items WHERE id = ?", (item_id,))
        db.commit()
        flash("Item deleted.", "info")
        return redirect(url_for("inventory"))

    @app.route("/health")
    def health():
        """Health-check endpoint. Returns JSON {"status": "ok"} with HTTP 200."""
        return jsonify({"status": "ok"}), 200

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(host="0.0.0.0", port=5000, debug=True)

