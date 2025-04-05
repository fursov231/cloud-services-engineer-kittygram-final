terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}



# Создание сети
resource "yandex_vpc_network" "network" {
  name = "network1"
}

# Создание подсети
resource "yandex_vpc_subnet" "subnet" {
  name = "subnet1"
  zone = "ru-central1-a"
  network_id = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.2.0.0/16"]
}

# Создание ВМ
resource "yandex_compute_instance" "vm" {
  name = "terraform-vm"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd87va5cc00gaq2f5qfb" # Ubuntu 20.04 LTS
    }
  }

   network_interface {
     subnet_id = yandex_vpc_subnet.subnet.id
     nat       = true
   }

   metadata = {
     ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
   }
 }