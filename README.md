# Задача
Ключевая задача — разработать отказоустойчивую инфраструктуру для сайта, включающую мониторинг, сбор логов и резервное копирование основных данных. Инфраструктура должна размещаться в Yandex Cloud.

## Инфраструктура
Для развёртки инфраструктуры используйте Terraform и Ansible.

Параметры виртуальной машины (ВМ) подбирайте по потребностям сервисов, которые будут на ней работать.

Ознакомьтесь со всеми пунктами из этой секции, не беритесь сразу выполнять задание, не дочитав до конца. Пункты взаимосвязаны и могут влиять друг на друга.

## Сайт
Создайте две ВМ в разных зонах, установите на них сервер nginx, если его там нет. ОС и содержимое ВМ должно быть идентичным, это будут наши веб-сервера.

Используйте набор статичных файлов для сайта. Можно переиспользовать сайт из домашнего задания.

Создайте Target Group, включите в неё две созданных ВМ.

Создайте Backend Group, настройте backends на target group, ранее созданную. Настройте healthcheck на корень (/) и порт 80, протокол HTTP.

Создайте HTTP router. Путь укажите — /, backend group — созданную ранее.

Создайте Application load balancer для распределения трафика на веб-сервера, созданные ранее. Укажите HTTP router, созданный ранее, задайте listener тип auto, порт 80.

### Для решения поставленной задачи используем следующий код Terraform:

```
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

```
### И следующий код Ansible
```
- name: настройка web
  hosts: web
  become: yes 
   
  tasks:

  - name: Установить необходимые пакеты
    apt:
      name:
        - nginx
        - apt-transport-https
        - wget
      state: present

  - name: Установить и настроить конфигурацию Nginx
    template: 
      src: default.conf.j2
      dest: /etc/nginx/sites-available/default
    notify:
      - Перезапустить Nginx

  - name: Set elasticsearch server IP
    set_fact:
      elasticsearch_server_ip: "{{ hostvars[groups['elasticsearch'][0]]['ansible_host'] }}"

  - name: Копировать файл test.html в каталог для веб-сайта
    copy:
      src: /home/drum/DevOps/test.html  # Укажите путь к файлу test.html на вашем компьютере
      dest: /var/www/html/test.html
      owner: www-data
      group: www-data
      mode: '0644'

  - name: Проверить файл test.html
    stat:
      path: /var/www/html/test.html
    register: test_html_file

  - name: Вывести информацию о файле
    debug:
      msg: "Файл теста существует: {{ test_html_file.stat.exists }}"

  - name: Убедиться, что Nginx запущен и включен
    service:
      name: nginx
      state: started
      enabled: yes

  - name: Перезапустить Nginx
    service:
      name: nginx
      state: restarted
```
## Мониторинг
Создайте ВМ, разверните на ней Zabbix. На каждую ВМ установите Zabbix Agent, настройте агенты на отправление метрик в Zabbix.

Настройте дешборды с отображением метрик, минимальный набор — по принципу USE (Utilization, Saturation, Errors) для CPU, RAM, диски, сеть, http запросов к веб-серверам. Добавьте необходимые tresholds на соответствующие графики.

### Для построения мониторинга создаем следующий ресурсы Terraform:
```
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
```
Для автоманитации развертования мониторинга, мной была зарание созданна БД Zabbix в которой был настроен Autoregistration actions

![image](https://github.com/user-attachments/assets/02402cc9-8ed6-4092-b4a5-6725816622b7)

А так же был настроен Templates который автоматически применяется для всех машин обращающихся к active server

![image](https://github.com/user-attachments/assets/f2784a16-77d5-447a-b22b-f6210a090e96)

В правиле DevOps были настроенны Items

![image](https://github.com/user-attachments/assets/ab8a8749-3705-447d-b256-aedc738376a8)

Созданны Triggers

![image](https://github.com/user-attachments/assets/660c5a4e-d2b1-42d8-8da4-ccec605a390c)




