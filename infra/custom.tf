# Настройка провайдера
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
Теперь усложним нашу инфраструктуру. Например, сделаем сервис по обработке изображений в Yandex Cloud с подробными комментариями:
# Простой Terraform-манифест для Yandex Cloud
# Создаём сервис-каталогизатор изображений с функцией и хранилищем

# Блок terraform определяет базовые настройки Terraform и указывает необходимые провайдеры
# Провайдер позволяет Terraform взаимодействовать с API облачных платформ
terraform {
required_providers {
yandex = {
source  = "yandex-cloud/yandex"      # Источник провайдера в реестре Terraform
version = "~> 0.89.0"                # Версия провайдера с допустимыми минорными обновлениями
}
}
}

# Конфигурируем провайдер Yandex Cloud с базовыми параметрами
# Зона доступности определяет физическое расположение ресурсов
# folder_id - это идентификатор каталога в Yandex Cloud, аналог проекта в других облаках
provider "yandex" {
zone      = "ru-central1-a"              # Зона доступности в Московском регионе
folder_id = var.folder_id                # Используем переменную для гибкости конфигурации
}

# Создаём виртуальную сеть - изолированный сетевой домен для наших ресурсов
# Сети в Yandex Cloud подобны VPC (Virtual Private Cloud) в других облачных провайдерах
resource "yandex_vpc_network" "image_network" {
name = "image-network"                   # Человекочитаемое название ресурса
}

# Создаём подсеть в рамках нашей виртуальной сети
# Подсеть - это диапазон IP-адресов внутри сети, привязанный к конкретной зоне доступности
resource "yandex_vpc_subnet" "image_subnet" {
name           = "image-subnet"          # Название подсети
zone           = "ru-central1-a"         # Зона доступности должна совпадать с провайдером
network_id     = yandex_vpc_network.image_network.id  # Связь с родительской сетью
v4_cidr_blocks = ["10.2.0.0/16"]         # Диапазон IP-адресов в нотации CIDR (65536 адресов)
}

# Создаём сервисный аккаунт - специальную учётную запись для выполнения операций от имени сервиса
# Сервисные аккаунты - это лучшая практика для безопасного выполнения облачных функций
resource "yandex_iam_service_account" "function_sa" {
name        = "image-function-sa"        # Название сервисного аккаунта
description = "Сервисный аккаунт для облачной функции"  # Описание для удобства администрирования
}

# Назначаем роль сервисному аккаунту через механизм IAM (Identity and Access Management)
# Роли определяют набор разрешений, которые имеет сервисный аккаунт
resource "yandex_resourcemanager_folder_iam_binding" "function_invoker" {
folder_id = var.folder_id                # Привязка к каталогу
role      = "serverless.functions.invoker"  # Роль, позволяющая вызывать функции
members = [
"serviceAccount:${yandex_iam_service_account.function_sa.id}",  # Формат указания сервисного аккаунта
]
}

# Создаём объектное хранилище (Object Storage) для изображений
# Object Storage - это сервис для хранения неструктурированных данных (файлов)
resource "yandex_storage_bucket" "image_storage" {
name     = "unique-image-storage-${var.folder_id}"  # Уникальное имя бакета с использованием ID каталога
# Имена бакетов должны быть глобально уникальными в рамках всего Yandex Cloud
max_size = 1073741824                   # Максимальный размер в байтах (1 ГБ)
}

# Создаём бессерверную функцию - кусок кода, который запускается по требованию
# Serverless Functions позволяют запускать код без необходимости управления серверами
resource "yandex_function" "image_processor" {
name               = "image-processor"   # Название функции
description        = "Функция для обработки изображений"  # Описание назначения
runtime            = "python39"          # Среда выполнения (Python 3.9)
entrypoint         = "index.handler"     # Точка входа в формате "файл.функция"
memory             = "128"               # Объём выделяемой памяти в МБ
execution_timeout  = "30"                # Максимальное время выполнения в секундах
service_account_id = yandex_iam_service_account.function_sa.id  # Связь с сервисным аккаунтом

# Переменные окружения доступны коду функции во время выполнения
environment = {
STORAGE_BUCKET = yandex_storage_bucket.image_storage.name  # Передаём имя бакета функции
}

# Содержимое функции - архив с кодом
# В реальном проекте здесь должен быть путь к архиву с вашим кодом
content {
zip_filename = "function.zip"         # Путь к ZIP-архиву с кодом функции
}
}

# Создаём триггер - механизм автоматического запуска функции при определённом событии
# Триггеры избавляют от необходимости вручную вызывать функцию
resource "yandex_function_trigger" "storage_trigger" {
name        = "image-trigger"           # Название триггера
description = "Триггер на загрузку изображений"  # Описание назначения

# Указываем функцию, которая будет вызываться триггером
function {
id                 = yandex_function.image_processor.id  # ID функции из предыдущего ресурса
service_account_id = yandex_iam_service_account.function_sa.id  # Сервисный аккаунт для вызова
}

# Настраиваем триггер объектного хранилища
# Этот триггер активируется при операциях с файлами в бакете
object_storage {
bucket_id = yandex_storage_bucket.image_storage.id  # ID бакета для мониторинга
create    = true                      # Активация при создании объектов
suffix    = ".jpg,.png,.gif"          # Фильтр по расширениям файлов
}
}

# Outputs - блок вывода значений после применения конфигурации
# Эти значения будут показаны пользователю после успешного выполнения terraform apply
output "function_id" {
value = yandex_function.image_processor.id  # Выводим ID созданной функции
description = "ID функции обработки изображений"  # Описание выходного значения
}

output "bucket_name" {
value = yandex_storage_bucket.image_storage.name  # Выводим имя созданного бакета
description = "Имя бакета для хранения изображений"  # Описание выходного значения
}

# Variables - блок переменных для параметризации конфигурации
# Переменные позволяют использовать один манифест в разных окружениях
variable "folder_id" {
description = "ID каталога в Yandex Cloud"  # Описание переменной
type        = string                       # Тип данных переменной
# Значение переменной можно задать через:
# - командную строку: terraform apply -var="folder_id=b1g12345678"
# - файл terraform.tfvars
# - переменную окружения TF_VAR_folder_id
}