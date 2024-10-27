terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "/home/drum/DevOps/authorized_key.json"
  folder_id = "b1goiv8hbuqegdqk3k0r"
}

resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name         = "subnet1"
  zone         = "ru-central1-a"
  network_id   = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["192.168.1.0/24"]
}

resource "yandex_vpc_subnet" "subnet-2" {
  name         = "subnet2"
  zone         = "ru-central1-b"
  network_id   = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["192.168.2.0/24"]
}

resource "yandex_vpc_security_group" "bastion_sg" {
  name = "bastion-sg"
  network_id = yandex_vpc_network.main_network.id

  ingress {
    protocol = "tcp"
    port     = 22
    # Разрешаем доступ по SSH только с IP адреса вашего рабочего места:
    # cidr_blocks = ["<your_ip_address>/32"]
    security_group_id = yandex_vpc_security_group.web_sg.id
  }
}

resource "yandex_vpc_security_group" "web_sg" {
  name = "web-sg"
  network_id = yandex_vpc_network.main_network.id

  ingress {
    protocol = "tcp"
    port     = 80
  }

  ingress {
    protocol = "tcp"
    port     = 443
  }
}

resource "yandex_vpc_security_group" "elasticsearch_sg" {
  name = "elasticsearch-sg"
  network_id = yandex_vpc_network.main_network.id

  ingress {
    protocol = "tcp"
    port     = 9200
  }
}

resource "yandex_compute_instance" "vm-1" {
  name = "vm-1"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8tvc3529h2cpjvpkr5"
      type     = "network-hdd"
      size     = 10
    }
  }

  security_group_ids = [yandex_vpc_security_group.web_sg.id]

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
  }

  metadata = {
    user-data = "${file("meta.txt")}"    
  }
}

resource "yandex_compute_instance" "vm-2" {
  name = "vm-2"
  zone = "ru-central1-b"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8tvc3529h2cpjvpkr5"
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-2.id
  }

  metadata = {
    user-data = "${file("meta.txt")}"    
  }
}

resource "yandex_compute_instance" "zabbix_server" {
  name = "zabbix-server"
    zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8tvc3529h2cpjvpkr5"  # ID образа с установленным Zabbix
      type     = "network-hdd"
      size     = 20
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat = true
  }

  security_group_ids = [yandex_vpc_security_group.web_sg.id]

  metadata = {
    user-data = "${file("meta.txt")}"    
  }
}

resource "yandex_compute_instance" "kibana" {
  name = "kibana"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8tvc3529h2cpjvpkr5"
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

  metadata = {
    user-data = "${file("meta.txt")}"    
  }
}

resource "yandex_compute_instance" "elasticsearch" {
  name = "elasticsearch"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8tvc3529h2cpjvpkr5"
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
  }

  security_group_ids = [yandex_vpc_security_group.elasticsearch_sg.id]

  metadata = {
    user-data = "${file("meta.txt")}"    
  }
}

resource "yandex_compute_instance" "bastion" {
  name = "bastion"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8tvc3529h2cpjvpkr5"
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
  }

  security_group_ids = [
    yandex_vpc_security_group.bastion_sg.id,
    yandex_vpc_security_group.web_sg.id
  ]
  

  metadata = {
    user-data = "${file("meta.txt")}"    
  }
}

resource "yandex_alb_target_group" "target_group" {
  name     = "my-target-group"

  target {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    ip_address = yandex_compute_instance.vm-1.network_interface.0.ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.subnet-2.id
    ip_address = yandex_compute_instance.vm-2.network_interface.0.ip_address
  }
}

resource "yandex_alb_backend_group" "backend_group" {
  name = "my-backend-group"
  
  http_backend {
    name = "test-http-backend"
    target_group_ids = ["${yandex_alb_target_group.target_group.id}"]
    weight = 1
    port = 80
    healthcheck {
      timeout = "1s"
      interval = "1s"
      http_healthcheck {
        path  = "/"
      }
    }    
  }
}

resource "yandex_alb_http_router" "http_router" {
  name          = "my-http-router"
}

resource "yandex_alb_virtual_host" "my-virtual-host" {
  name      = "my-virtual-host"
  http_router_id = yandex_alb_http_router.http_router.id
  route {
    name = "my-route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.backend_group.id
        timeout = "3s"
      }
    }
  }
}

resource "yandex_alb_load_balancer" "test-balancer" {
  name        = "my-load-balancer"

  network_id  = yandex_vpc_network.network-1.id
  
  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.subnet-1.id 
    }
    location {
      zone_id   = "ru-central1-b"
      subnet_id = yandex_vpc_subnet.subnet-2.id 
    }
  }
  
  listener {
    name = "my-listener"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [ 80 ]
    }    
    http {
      handler {
        http_router_id = yandex_alb_http_router.http_router.id
      }
    }
  }
}

output "internal_ip_address_vm_1" {
  value = yandex_compute_instance.vm-1.network_interface.0.ip_address
}

output "internal_ip_address_vm_2" {
  value = yandex_compute_instance.vm-2.network_interface.0.ip_address
}

output "external_ip_yandex_alb_load_balancer" {
  value = yandex_alb_load_balancer.test-balancer.listener.0
}


output "external_ip_address_zabbix_server" {
  value = yandex_compute_instance.zabbix_server.network_interface.0.nat_ip_address
}

output "external_ip_address_kibana" {
  value = yandex_compute_instance.kibana.network_interface.0.nat_ip_address
}

output "external_ip_address_bastion" {
  value = yandex_compute_instance.bastion.network_interface.0.nat_ip_address
}
