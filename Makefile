# Read project name from .env file
$(shell cp -n \.env.default \.env)
$(shell cp -n \.\/docker\/docker-compose\.override\.yml\.default \.\/docker\/docker-compose\.override\.yml)
include .env

DB_URL := sqlite:///dev/shm/dwt.sqlite

PHPCS_EXTS := php,inc,install,module,theme,profile,info
PHPCS_IGNORE := *.css,*.md,libraries/*,contrib/*,features/*,modified/*

# Get local values only once.
LOCAL_UID := $(shell id -u)
LOCAL_GID := $(shell id -g)

# Evaluate recursively.
CUID ?= $(LOCAL_UID)
CGID ?= $(LOCAL_GID)

COMPOSE_NET_NAME := $(shell echo $(COMPOSE_PROJECT_NAME) | tr '[:upper:]' '[:lower:]'| sed -r 's/[^a-z0-9]+//g')_front

php = docker-compose exec -T --user $(CUID):$(CGID) php time ${1}
php-0 = docker-compose exec -T php time ${1}

all: | include net build install prepare si info

include:
ifeq ($(strip $(COMPOSE_PROJECT_NAME)),projectname)
#todo: ask user to make a project name and mv folders.
$(error Project name can not be default, please edit ".env" and set COMPOSE_PROJECT_NAME variable.)
endif

build: clean
	mkdir -p web
	mkdir -p web/sites/all/modules/custom
	#mkdir -p /dev/shm/${COMPOSE_PROJECT_NAME}_mysql

install:
	@echo "Updating containers..."
	docker-compose pull --parallel
	@echo "Build and run containers..."
	docker-compose up -d --remove-orphans
	$(call php-0, apk add --no-cache git rsync)
	$(call php-0, chown $(CUID):$(CGID) .)

prepare:
	$(call php, drush dl -y --destination=/tmp drupal-7.56)
	$(call php, sh -c "rsync -ax /tmp/drupal-7.56/* /var/www/html")
	$(call php, rm -rf /tmp/drupal-7.56)
	$(call php, drush dl -y ctools diff entity entityreference features rules strongarm views)

si:
	$(call php, drush si -y --account-pass=admin --db-url=$(DB_URL))
	$(call php, drush en -y watchtower_storage dw_server dw_client views_ui)
	make -s info

info:
ifeq ($(shell docker inspect --format="{{ .State.Running }}" $(COMPOSE_PROJECT_NAME)_web 2> /dev/null),true)
	@echo Project IP: $(shell docker inspect --format='{{.NetworkSettings.Networks.$(COMPOSE_NET_NAME).IPAddress}}' $(COMPOSE_PROJECT_NAME)_web)
endif
ifeq ($(shell docker inspect --format="{{ .State.Running }}" $(COMPOSE_PROJECT_NAME)_mail 2> /dev/null),true)
	@echo Mailhog IP: $(shell docker inspect --format='{{.NetworkSettings.Networks.$(COMPOSE_NET_NAME).IPAddress}}' $(COMPOSE_PROJECT_NAME)_mail)
endif
ifeq ($(shell docker inspect --format="{{ .State.Running }}" $(COMPOSE_PROJECT_NAME)_adminer 2> /dev/null),true)
	@echo Adminer IP: $(shell docker inspect --format='{{.NetworkSettings.Networks.$(COMPOSE_NET_NAME).IPAddress}}' $(COMPOSE_PROJECT_NAME)_adminer)
endif

chown:
# Use this goal to set permissions in docker container
	docker-compose exec -T php /bin/sh -c "chown $(shell id -u):$(shell id -g) /var/www/html -R"
# Need this to fix files folder
	docker-compose exec -T php /bin/sh -c "chown www-data: /var/www/html/sites/default/files -R"

exec:
	docker-compose exec --user $(CUID):$(CGID) php ash

exec0:
	docker-compose exec php ash

clean: down
	@echo "Clean-up for $(COMPOSE_PROJECT_NAME)"
	if [ -d "web" ]; then docker run --rm -v $(shell pwd):/mnt skilldlabs/$(PHP_IMAGE) ash -c "rm -rf /mnt/web"; fi

down: info
	@echo "Removing composition for $(COMPOSE_PROJECT_NAME)"
	docker-compose down --remove-orphans

net:
ifeq ($(strip $(shell docker network ls | grep $(COMPOSE_PROJECT_NAME))),)
	docker network create $(COMPOSE_NET_NAME)
endif
	@make -s iprange

iprange:
	$(shell grep -q -F 'IPRANGE=' .env || echo "\nIPRANGE=$(shell docker network inspect $(COMPOSE_NET_NAME) --format '{{(index .IPAM.Config 0).Subnet}}')" >> .env)

phpcs:
	docker run --rm \
		-v $(shell pwd)/watchtower:/work/modules \
		skilldlabs/docker-phpcs-drupal phpcs -s --colors \
		--standard=Drupal,DrupalPractice \
		--extensions=$(PHPCS_EXTS) \
		--ignore=$(PHPCS_IGNORE),*.js .

phpcbf:
	docker run --rm \
		-v $(shell pwd)/watchtower:/work/modules \
		skilldlabs/docker-phpcs-drupal phpcbf -s --colors \
		--standard=Drupal,DrupalPractice \
		--extensions=$(PHPCS_EXTS) \
		--ignore=$(PHPCS_IGNORE),*.js .
