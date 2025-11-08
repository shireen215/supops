output "alb_dns" {
  description = "ALB DNS name"
  value       = aws_lb.alb.dns_name
}