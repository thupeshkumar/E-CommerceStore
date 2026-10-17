output "public_ip" { value = aws_instance.app.public_ip }
output "public_dns" { value = aws_instance.app.public_dns }
output "frontend_url" { value = "http://${aws_instance.app.public_ip}" }
output "ssh_command" { value = "ssh -i /path/to/key.pem ubuntu@${aws_instance.app.public_ip}" }
