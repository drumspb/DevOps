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

### Zabbix server а так же дамп базы автоматически подгружается в облако следующим кодом Ansible:
```
- name: Install Zabbix Server
  hosts: zabbix_server
  become: true
  vars:
    ansible_remote_tmp: /tmp/.ansible-${USER}

  tasks:
    - name: Скачать пакет репозитория Zabbix
      get_url:
        url: https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb
        dest: /tmp/zabbix-release_7.0-2+ubuntu24.04_all.deb

    - name: Установить пакет репозитория Zabbix с помощью dpkg
      command: sudo dpkg -i /tmp/zabbix-release_7.0-2+ubuntu24.04_all.deb

    - name: Обновить пакетный список apt после установки репозитория Zabbix
      apt:
        update_cache: yes

    - name: Install required packages
      apt:
        name:
          - acl
          - python3-pip
          - python3-psycopg2
          - postgresql
          - zabbix-server-pgsql
          - zabbix-frontend-php
          - php8.3-pgsql
          - zabbix-apache-conf
          - zabbix-sql-scripts
          - zabbix-agent
        state: present

    - name: Создать резервную копию pg_hba.conf
      copy:
        src: /etc/postgresql/16/main/pg_hba.conf  # Замените на ваш путь
        dest: /etc/postgresql/16/main/pg_hba.conf.bak
        remote_src: yes

    - name: Изменения правил подключения для postgres
      community.postgresql.postgresql_pg_hba:
        dest: /etc/postgresql/16/main/pg_hba.conf
        contype: local
        databases: all
        users: postgres
        state: present
        method: trust

    - name: Перезапустить PostgreSQL
      service:
        name: postgresql
        state: restarted        
   
    - name: Create Zabbix database user
      become: true
      become_method: enable
      become_user: postgres
      community.postgresql.postgresql_user:
        name: zabbix
        password: password
        state: present

    - name: Загрузка файла на ansible хост
      ansible.builtin.copy:
        src: /home/drum/DevOps/zabbix.dump
        dest: /tmp/zabbix.dump

    - name: Create Zabbix database
      become_user: postgres
      postgresql_db:
        name: zabbix
        owner: zabbix

    - name: Restore базы zabbix на зарание созданную
      become: true
      become_method: enable
      become_user: postgres
      community.postgresql.postgresql_db:
        name: zabbix
        state: restore
        target: /tmp/zabbix.dump

    - name: Configure Zabbix server
      lineinfile:
        path: /etc/zabbix/zabbix_server.conf
        regexp: '^DBPassword='
        line: 'DBPassword=password'
        state: present

    - name: Restart services
      systemd:
        name: "{{ item }}"
        state: restarted
        enabled: true
      loop:
        - zabbix-server
        - zabbix-agent
        - apache2
```
Zabbix agent:
```
- name: Install Zabbix agent
  hosts: all
  become: true
  vars:
    ansible_remote_tmp: /tmp/.ansible-${USER}

  tasks:
    - name: Get Zabbix server IP
      set_fact:
        zabbix_server_ip: "{{ item }}"
      loop: "{{ groups['zabbix_server'] }}"
      when: "inventory_hostname != item"

    - name: Скачать пакет репозитория Zabbix
      get_url:
        url: https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb
        dest: /tmp/zabbix-release_7.0-2+ubuntu24.04_all.deb

    - name: Установить пакет репозитория Zabbix с помощью dpkg
      command: sudo dpkg -i /tmp/zabbix-release_7.0-2+ubuntu24.04_all.deb

    - name: Обновить пакетный список apt после установки репозитория Zabbix
      apt:
        update_cache: yes   

    - name: Install required packages
      apt:
        name:
          - zabbix-agent2
          - zabbix-agent2-plugin-*
        state: present

    - name: Update Server parameter
      ansible.builtin.replace:
        path: /etc/zabbix/zabbix_agent2.conf
        regexp: '^Server=.*'
        replace: 'Server={{ zabbix_server_ip }}'
        backup: yes  # Создать резервную копию файла перед изменением

    - name: Update ActiveServer parameter
      ansible.builtin.replace:
        path: /etc/zabbix/zabbix_agent2.conf
        regexp: '^ServerActive=.*'
        replace: 'ServerActive={{ zabbix_server_ip }}'
        backup: yes  # Создать резервную копию файла перед изменением

    - name: Update ActiveServer parameter
      ansible.builtin.replace:
        path: /etc/zabbix/zabbix_agent2.conf
        regexp: '^Hostname=.*'
        replace: 'Hostname={{ inventory_hostname }}'
        backup: yes  # Создать резервную копию файла перед изменением        

    - name: Restart services
      systemd:
        name: "{{ item }}"
        state: restarted
        enabled: true
      loop:
        - zabbix-agent2     
```

## Логи
Cоздайте ВМ, разверните на ней Elasticsearch. Установите filebeat в ВМ к веб-серверам, настройте на отправку access.log, error.log nginx в Elasticsearch.

Создайте ВМ, разверните на ней Kibana, сконфигурируйте соединение с Elasticsearch.

### Для построения ELK стека используем следующие ресурсы Terraform:
```
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
```

### Для настройки ВМ с помощью Ansible будем использовать docker образы:
```
- name: Install  Docker
  hosts: elasticsearch, kibana, web
  become: true

  tasks:

    - name: Update APT package index
      apt:
        update_cache: yes


    - name: install dependencies
      apt:
        name: "{{item}}"
        state: present
        update_cache: yes
      loop:
        - apt-transport-https
        - ca-certificates
        - curl
        - gnupg-agent
        - software-properties-common

    - name: add GPG key
      apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present

    - name: add docker repository to apt
      apt_repository:
        repo: deb https://download.docker.com/linux/ubuntu bionic stable
        state: present

    - name: Update APT package index (after adding Docker repository)
      apt:
        update_cache: yes

    - name: Install Docker packages
      apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-buildx-plugin
          - docker-compose-plugin
        state: latest

    - name: Ensure the current user is added to the docker group
      user:
        name: "{{ ansible_user }}"  # текущий пользователь
        group: docker
        append: yes

    - name: Start and enable Docker
      systemd:
        name: docker
        state: started
        enabled: yes

- name: Install  elasticsearch
  hosts: elasticsearch
  become: true

  tasks:

    - name: Run Bitnami Elasticsearch container
      docker_container:
        name: elasticsearch
        image: bitnami/elasticsearch:latest
        state: started
        restart_policy: unless-stopped
        published_ports:
          - "9200:9200"
        env:
          discovery.type: single-node
          ES_JAVA_OPTS: "-Xms512m -Xmx512m"

- name: Install  kibana
  hosts: kibana
  become: true

  tasks:          

    - name: Set elasticsearch server IP
      set_fact:
        elasticsearch_server_ip: "{{ hostvars[groups['elasticsearch'][0]]['ansible_host'] }}"

    - name: Run Bitnami Kibana container
      docker_container:
        name: kibana
        image: bitnami/kibana:latest
        state: started
        restart_policy: unless-stopped
        published_ports:
          - "5601:5601"
        env:
          KIBANA_ELASTICSEARCH_URL: "http://{{ elasticsearch_server_ip }}:9200"           


- name: настройка web
  hosts: web
  become: yes 
   
  tasks:

  - name: Set elasticsearch server IP
    set_fact:
      elasticsearch_server_ip: "{{ hostvars[groups['elasticsearch'][0]]['ansible_host'] }}"

  - name: Create directory for Filebeat config
    file:
      path: /etc/filebeat
      state: directory
      mode: '0755'

  - name: Copy Filebeat configuration
    copy:
      dest: /etc/filebeat/filebeat.yml
      content: |
        filebeat.inputs:
          - type: log
            enabled: true
            paths:
              - /var/log/nginx/access.log
              - /var/log/nginx/error.log
            fields:
              service: nginx

        output.elasticsearch:
          hosts: ["http://{{ elasticsearch_server_ip }}:9200"]    

  - name: Run Filebeat Docker container
    docker_container:
      name: filebeat
      image: chainguard/filebeat:latest  
      state: started
      restart_policy: unless-stopped
      volumes:
        - /var/log/nginx:/var/log/nginx  # Монтируем логи Nginx
        - /etc/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml  # Конфигурация Filebeat
      network_mode: "host"  # Или используйте подходящую настройку сети

  - name: Ensure permissions on log files
    file:
      path: /var/log/nginx
      owner: root
      group: root
      mode: '0755'
```

### Сеть
Разверните один VPC. Сервера web, Elasticsearch поместите в приватные подсети. Сервера Zabbix, Kibana, application load balancer определите в публичную подсеть.

Настройте Security Groups соответствующих сервисов на входящий трафик только к нужным портам.

Настройте ВМ с публичным адресом, в которой будет открыт только один порт — ssh. Настройте все security groups на разрешение входящего ssh из этой security group. Эта вм будет реализовывать концепцию bastion host. Потом можно будет подключаться по ssh ко всем хостам через этот хост.

### Для решения данной задачи добавляем в код Terraform еще одну ВМ, создаем группы безопастности и добавляем правила для каждой ВМ
```
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
```
