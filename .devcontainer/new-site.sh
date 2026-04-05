
SITE_NAME=${1:-"development.localhost"}
DB_NAME=${2:-"dev_db"}
ROOT_PASS=${3:-"123"}

bench new-site "$SITE_NAME" --db-name "$DB_NAME" --mariadb-root-password "$ROOT_PASS"


# patch to allow connection from any ip address
CONTAINER_IP=$(hostname -i)
mysql -u root -p"$ROOT_PASS" -h mariadb -e "RENAME USER '$DB_NAME'@'$CONTAINER_IP' TO '$DB_NAME'@'%'; FLUSH PRIVILEGES;"
