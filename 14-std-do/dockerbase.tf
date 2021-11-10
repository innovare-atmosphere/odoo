variable "database_password" {
    default = ""
}

variable "domain" {
    default = ""
}

variable "webmaster_email" {
    default = ""
}

resource "random_password" "database_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "digitalocean_droplet" "www-odoo" {
  image = "docker-20-04"
  name = "www-1"
  region = "nyc3"
  size = "s-1vcpu-1gb"
  ssh_keys = [
    digitalocean_ssh_key.terraform.id
  ]

  connection {
    host = self.ipv4_address
    user = "root"
    type = "ssh"
    private_key = var.pvt_key != "" ? file(var.pvt_key) : tls_private_key.pk.private_key_pem
    timeout = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/bin",
      # install nginx
      "sudo apt update",
      "sudo apt install -y nginx",
      "sudo apt install -y python3-certbot-nginx",
      # create odoo installation directory
      "mkdir /root/odoo",
      "mkdir /root/odoo/addons",
      "mkdir /root/odoo/config"
    ]
  }

  provisioner "file" {
    content      = templatefile("docker-compose.yml.tpl", {
      database_password = var.database_password != "" ? var.database_password : random_password.database_password.result
    })
    destination = "/root/odoo/docker-compose.yml"
  }

  provisioner "file" {
    content      = templatefile("atmosphere-nginx.conf.tpl", {
      server_name = var.domain != "" ? var.domain : "0.0.0.0"
    })
    destination = "/etc/nginx/conf.d/atmosphere-nginx.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/bin",
      # run compose
      "cd /root/odoo",
      "docker-compose up -d",
      "rm /etc/nginx/sites-enabled/default",
      "systemctl restart nginx",
      "ufw allow http",
      "ufw allow https",
      "%{if var.domain!= ""}certbot --nginx --non-interactive --agree-tos --domains ${var.domain} %{if var.webmaster_email!= ""} --email ${var.webmaster_email} %{ else } --register-unsafely-without-email %{ endif } %{ else }echo NOCERTBOT%{ endif }"
    ]
  }
}