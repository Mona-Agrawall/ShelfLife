output "jenkins_url" {
  description = "Jenkins web UI URL"
  value       = "http://${aws_eip.jenkins_eip.public_ip}:8080"
}

output "app_url" {
  description = "ShelfLife application URL"
  value       = "http://${aws_eip.app_eip.public_ip}"
}

output "jenkins_ip" {
  description = "Jenkins server public IP"
  value       = aws_eip.jenkins_eip.public_ip
}

output "app_ip" {
  description = "Application server public IP"
  value       = aws_eip.app_eip.public_ip
}

output "ssh_jenkins" {
  description = "SSH command to connect to Jenkins server"
  value       = "ssh -i shelflife-key.pem ubuntu@${aws_eip.jenkins_eip.public_ip}"
}

output "ssh_app" {
  description = "SSH command to connect to application server"
  value       = "ssh -i shelflife-key.pem ubuntu@${aws_eip.app_eip.public_ip}"
}

output "private_key_path" {
  description = "Path to the generated private key file"
  value       = local_file.private_key.filename
}
