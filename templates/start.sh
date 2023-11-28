#!/bin/sh
MOUNT_DIR=/srv/www
NFS_ENDPOINT=${nfs_endpoint}
CONTAINER_NAME=${element(split(".",nfs_endpoint),0)}
BLOB_STORAGE_NAME=${blob_storage_name}
WORDPRESS_VERSION=${wordpress_version}

apt update -y && apt upgrade -y

if [ ! -z NFS_ENDPOINT ]; then
    apt install -y nfs-common  \
                apache2 \
                ghostscript \
                libapache2-mod-php \
                mysql-server \
                php \
                php-bcmath \
                php-curl \
                php-imagick \
                php-intl \
                php-json \
                php-mbstring \
                php-mysql \
                php-xml \
                php-zip

    mkdir -p $MOUNT_DIR
    mount.nfs -o sec=sys,vers=3,nolock,proto=tcp $NFS_ENDPOINT:/$CONTAINER_NAME/$BLOB_STORAGE_NAME $MOUNT_DIR
    if [ -z "$(ls -A $MOUNT_DIR)" ];
    then
        wget https://wordpress.org/wordpress-$WORDPRESS_VERSION.tar.gz
        tar -xzf wordpress-$WORDPRESS_VERSION.tar.gz -C $MOUNT_DIR
        chown -R www-data: $MOUNT_DIR
    fi
    cat <<EOF >> /etc/apache2/sites-available/wordpress.conf
<VirtualHost *:80>
    DocumentRoot $MOUNT_DIR/wordpress
    <Directory $MOUNT_DIR/wordpress>
        Options FollowSymLinks
        AllowOverride Limit Options FileInfo
        DirectoryIndex index.php
        Require all granted
    </Directory>
    <Directory $MOUNT_DIR/wordpress/wp-content>
        Options FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>
EOF
    a2ensite wordpress
    a2enmod rewrite
    a2dissite 000-default
    service apache2 reload
else
    echo "No NFS endpoint to mount, skipping !"
fi
# Configure MySQL for WordPress
    MYSQL_ROOT_PASSWORD="wor"
    MYSQL_DATABASE="wordpress"
    MYSQL_USER="wordpress"
    MYSQL_PASSWORD="wor"

    echo "CREATE DATABASE $MYSQL_DATABASE;" | mysql -u root -p$MYSQL_ROOT_PASSWORD
    echo "CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';" | mysql -u root -p$MYSQL_ROOT_PASSWORD
    echo "GRANT ALL PRIVILEGES ON $MYSQL_DATABASE.* TO '$MYSQL_USER'@'localhost';" | mysql -u root -p$MYSQL_ROOT_PASSWORD
    echo "FLUSH PRIVILEGES;" | mysql -u root -p$MYSQL_ROOT_PASSWORD

else
    echo "No NFS endpoint to mount, skipping!"
fi