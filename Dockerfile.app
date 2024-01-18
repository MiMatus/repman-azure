FROM buddy/repman:1.3.4

CMD ["/bin/bash", "-c", "/app/bin/console d:m:m --no-interaction && /app/bin/console messenger:setup-transports --no-interaction && /app/bin/console repman:security:update-db && /app/bin/console assets:install && php-fpm"]
