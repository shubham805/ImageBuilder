#!/bin/bash

# set -e

php -v

# if defined, assume the container is running on Azure
AZURE_DETECTED=$WEBSITES_ENABLE_APP_SERVICE_STORAGE


update_php_config() {
	local CONFIG_FILE="${1}"
	local PARAM_NAME="${2}"
	local PARAM_VALUE="${3}"
	local VALUE_TYPE="${4}"
	local PARAM_UPPER_BOUND="${5}"

	if [[ -e $CONFIG_FILE && $PARAM_VALUE ]]; then
		local FINAL_PARAM_VALUE

		if [[ "$VALUE_TYPE" == "NUM" && $PARAM_VALUE =~ ^[0-9]+$ && $PARAM_UPPER_BOUND =~ ^[0-9]+$ ]]; then

			if [[ "$PARAM_VALUE" -le "$PARAM_UPPER_BOUND" ]]; then
				FINAL_PARAM_VALUE=$PARAM_VALUE
			else
				FINAL_PARAM_VALUE=$PARAM_UPPER_BOUND
			fi

		elif [[ "$VALUE_TYPE" == "MEM" && $PARAM_VALUE =~ ^[0-9]+M$ && $PARAM_UPPER_BOUND =~ ^[0-9]+M$ ]]; then

			if [[ "${PARAM_VALUE::-1}" -le "${PARAM_UPPER_BOUND::-1}" ]]; then
				FINAL_PARAM_VALUE=$PARAM_VALUE
			else
				FINAL_PARAM_VALUE=$PARAM_UPPER_BOUND
			fi

		elif [[ "$VALUE_TYPE" == "TOGGLE" ]] && [[ "$PARAM_VALUE" == "On" || "$PARAM_VALUE" == "Off" ]]; then
			FINAL_PARAM_VALUE=$PARAM_VALUE
		fi


		if [[ $FINAL_PARAM_VALUE ]]; then
			echo "updating php config value "$PARAM_NAME
			sed -i "s/.*$PARAM_NAME.*/$PARAM_NAME = $FINAL_PARAM_VALUE/" $CONFIG_FILE
		fi
	fi
}

setup_wordpress() {
    if [ ! -d $WORDPRESS_LOCK_HOME ]; then
        mkdir -p $WORDPRESS_LOCK_HOME
    fi

    if [ ! -e $WORDPRESS_LOCK_FILE ]; then
        echo "INFO: creating a new WordPress status lock file ..."
        touch $WORDPRESS_LOCK_FILE;
    else 
        echo "INFO: Found an existing WordPress status lock file ..."
    fi

    if [ ! $(grep "GIT_PULL_COMPLETED" $WORDPRESS_LOCK_FILE) ]; then
        while [ -d $WORDPRESS_HOME ]
        do
            mkdir -p /home/bak
            mv $WORDPRESS_HOME /home/bak/wordpress_bak$(date +%s)            
        done
        
        GIT_REPO=${GIT_REPO:-https://github.com/azureappserviceoss/wordpress-azure}
	    GIT_BRANCH=${GIT_BRANCH:-linux-appservice}
	    echo "INFO: ++++++++++++++++++++++++++++++++++++++++++++++++++:"
	    echo "REPO: "$GIT_REPO
	    echo "BRANCH: "$GIT_BRANCH
	    echo "INFO: ++++++++++++++++++++++++++++++++++++++++++++++++++:"
    
	    echo "INFO: Clone from "$GIT_REPO		
        git clone $GIT_REPO $WORDPRESS_HOME	&& cd $WORDPRESS_HOME
	    if [ "$GIT_BRANCH" != "master" ];then
		    echo "INFO: Checkout to "$GIT_BRANCH
		    git fetch origin
	        git branch --track $GIT_BRANCH origin/$GIT_BRANCH && git checkout $GIT_BRANCH
	    fi

        #remove .git
        rm  -rf $WORDPRESS_HOME/.git
        echo "GIT_PULL_COMPLETED" >> $WORDPRESS_LOCK_FILE
    fi

    if [ ! $(grep "WP_INSTALLATION_COMPLETED" $WORDPRESS_LOCK_FILE) ]; then
        wp core install --url=$WEBSITE_HOSTNAME --title="${WORDPRESS_TITLE}" --admin_user=$WORDPRESS_ADMIN_USER --admin_password=$WORDPRESS_ADMIN_PASSWORD --admin_email=$WORDPRESS_ADMIN_EMAIL --skip-email --path=$WORDPRESS_HOME --allow-root
        echo "WP_INSTALLATION_COMPLETED" >> $WORDPRESS_LOCK_FILE
    fi

    if [ $(grep "WP_INSTALLATION_COMPLETED" $WORDPRESS_LOCK_FILE) ] && [ ! $(grep "WP_CONFIG_UPDATED" $WORDPRESS_LOCK_FILE) ]; then
        wp rewrite structure '/%year%/%monthnum%/%day%/%postname%/' --path=$WORDPRESS_HOME --allow-root
        wp option set rss_user_excerpt 1 --path=$WORDPRESS_HOME --allow-root
        wp option set page_comments 1 --path=$WORDPRESS_HOME --allow-root
        echo "WP_CONFIG_UPDATED" >> $WORDPRESS_LOCK_FILE
    fi

    if [ $(grep "WP_INSTALLATION_COMPLETED" $WORDPRESS_LOCK_FILE) ] && [ ! $(grep "SMUSH_PLUGIN_INSTALLED" $WORDPRESS_LOCK_FILE) ]; then
        wp plugin install wp-smushit --force --activate --path=$WORDPRESS_HOME --allow-root
        echo "SMUSH_PLUGIN_INSTALLED" >> $WORDPRESS_LOCK_FILE
    fi

    if [ $(grep "SMUSH_PLUGIN_INSTALLED" $WORDPRESS_LOCK_FILE) ] && [ ! $(grep "SMUSH_PLUGIN_CONFIG_UPDATED" $WORDPRESS_LOCK_FILE) ]; then
        wp option set skip-smush-setup 1 --path=$WORDPRESS_HOME --allow-root
        wp option patch update wp-smush-settings auto 1 --path=$WORDPRESS_HOME --allow-root
        wp option patch update wp-smush-settings lossy 0 --path=$WORDPRESS_HOME --allow-root
        wp option patch update wp-smush-settings strip_exif 1 --path=$WORDPRESS_HOME --allow-root
        wp option patch update wp-smush-settings original 1 --path=$WORDPRESS_HOME --allow-root
        wp option patch update wp-smush-settings lazy_load 0 --path=$WORDPRESS_HOME --allow-root
        wp option patch update wp-smush-settings usage 0 --path=$WORDPRESS_HOME --allow-root
        echo "SMUSH_PLUGIN_CONFIG_UPDATED" >> $WORDPRESS_LOCK_FILE
    fi

    if [ $(grep "WP_INSTALLATION_COMPLETED" $WORDPRESS_LOCK_FILE) ] && [ ! $(grep "W3TC_PLUGIN_INSTALLED" $WORDPRESS_LOCK_FILE) ]; then
        wp plugin install w3-total-cache --force --activate --path=$WORDPRESS_HOME --allow-root
        echo "W3TC_PLUGIN_INSTALLED" >> $WORDPRESS_LOCK_FILE
    fi

    if [ $(grep "W3TC_PLUGIN_INSTALLED" $WORDPRESS_LOCK_FILE) ] && [ ! $(grep "W3TC_PLUGIN_CONFIG_UPDATED" $WORDPRESS_LOCK_FILE) ]; then
        wp w3-total-cache import $WORDPRESS_SOURCE/w3tc-config.json --path=$WORDPRESS_HOME --allow-root
        echo "W3TC_PLUGIN_CONFIG_UPDATED" >> $WORDPRESS_LOCK_FILE
    fi    

    # Although in AZURE, we still need below chown cmd.
    chown -R nginx:nginx $WORDPRESS_HOME
}


# setup_wordpress_old(){
# 	if ! [ -e WORDPRESS_LOCK_PATH/version.php ]; then
#         echo "INFO: There in no wordpress, going to GIT pull...:"
#         while [ -d $WORDPRESS_HOME ]
#         do
#             mkdir -p /home/bak
#             mv $WORDPRESS_HOME /home/bak/wordpress_bak$(date +%s)            
#         done
#         #remove all files in WORDPRESS_HOME before cloning repo
#         #rm -rf $WORDPRESS_HOME/*
        
#         GIT_REPO=${GIT_REPO:-https://github.com/azureappserviceoss/wordpress-azure}
# 	    GIT_BRANCH=${GIT_BRANCH:-linux-appservice}
# 	    echo "INFO: ++++++++++++++++++++++++++++++++++++++++++++++++++:"
# 	    echo "REPO: "$GIT_REPO
# 	    echo "BRANCH: "$GIT_BRANCH
# 	    echo "INFO: ++++++++++++++++++++++++++++++++++++++++++++++++++:"
    
# 	    echo "INFO: Clone from "$GIT_REPO		
#         git clone $GIT_REPO $WORDPRESS_HOME	&& cd $WORDPRESS_HOME
# 	    if [ "$GIT_BRANCH" != "master" ];then
# 		    echo "INFO: Checkout to "$GIT_BRANCH
# 		    git fetch origin
# 	        git branch --track $GIT_BRANCH origin/$GIT_BRANCH && git checkout $GIT_BRANCH
# 	    fi

#         #remove .git
#         rm  -rf $WORDPRESS_HOME/.git
        
#         echo "INFO: Installing WordPress..."
#         wp core install --url=$WEBSITE_HOSTNAME --title="${WORDPRESS_TITLE}" --admin_user=$WORDPRESS_ADMIN_USER --admin_password=$WORDPRESS_ADMIN_PASSWORD --admin_email=$WORDPRESS_ADMIN_EMAIL --skip-email --path=$WORDPRESS_HOME --allow-root
#         wp rewrite structure '/%year%/%monthnum%/%day%/%postname%/' --path=$WORDPRESS_HOME --allow-root
#         wp option set rss_user_excerpt 1 --path=$WORDPRESS_HOME --allow-root
#         wp option set page_comments 1 --path=$WORDPRESS_HOME --allow-root

#         echo "INFO: Installing W3TC plugin..."
#         wp plugin install w3-total-cache --activate --path=$WORDPRESS_HOME --debug --allow-root
#         wp w3-total-cache import $WORDPRESS_SOURCE/w3tc-config.json --path=$WORDPRESS_HOME --allow-root

#         echo "INFO: Installing Smush plugin..."
#         wp plugin install wp-smushit --activate --path=$WORDPRESS_HOME --allow-root
#         wp option set skip-smush-setup 1 --path=$WORDPRESS_HOME --allow-root
#         wp option patch update wp-smush-settings auto 1 --path=$WORDPRESS_HOME --allow-root
#         wp option patch update wp-smush-settings lossy 0 --path=$WORDPRESS_HOME --allow-root
#         wp option patch update wp-smush-settings strip_exif 1 --path=$WORDPRESS_HOME --allow-root
#         wp option patch update wp-smush-settings original 1 --path=$WORDPRESS_HOME --allow-root
#         wp option patch update wp-smush-settings lazy_load 0 --path=$WORDPRESS_HOME --allow-root
#         wp option patch update wp-smush-settings usage 0 --path=$WORDPRESS_HOME --allow-root

#     else
#         echo "INFO: Wordpress already exists, no need to GIT pull again."
#     fi
	
# 	# Although in AZURE, we still need below chown cmd.
#     chown -R nginx:nginx $WORDPRESS_HOME
#}


# # That wp-config.php doesn't exist means WordPress is not installed/configured yet.
# if [ ! -e "$WORDPRESS_HOME/wp-config.php" ] || [ ! -e "$WORDPRESS_HOME/wp-includes/version.php" ]; then
# 	echo "INFO: $WORDPRESS_HOME/wp-config.php or wp-includes/version.php not found."
# 	echo "Installing WordPress ..."
# 	setup_wordpress_old
# 	echo "Wordpress Setup Complete ..."
# else 
# 	echo "INFO: WordPress is already installed ... skipping setup"
# fi

if ! [[ $SKIP_WP_INSTALLATION ]] || ! [[ "$SKIP_WP_INSTALLATION" == "true" 
    || "$SKIP_WP_INSTALLATION" == "TRUE" || "$SKIP_WP_INSTALLATION" == "True" ]]; then
    setup_wordpress
else 
    echo "INFO: Skipping WP installation..."
fi

if [ -e "$WORDPRESS_HOME/wp-config.php" ]; then
    echo "INFO: Check SSL Setting..."    
    SSL_DETECTED=$(grep "\$_SERVER\['HTTPS'\] = 'on';" $WORDPRESS_HOME/wp-config.php)
    if [ ! SSL_DETECTED ];then
        echo "INFO: Add SSL Setting..."
        sed -i "/stop editing!/r $WORDPRESS_SOURCE/ssl-settings.txt" $WORDPRESS_HOME/wp-config.php        
    else        
        echo "INFO: SSL Settings exist!"
    fi
fi

# set permalink as 'Day and Name' and default, it has best performance with nginx re_write config.
# PERMALINK_DETECTED=$(grep "\$wp_rewrite->set_permalink_structure" $WORDPRESS_HOME/wp-settings.php)
# if [ ! $PERMALINK_DETECTED ];then
#     echo "INFO: Set Permalink..."
#     init_string="do_action( 'init' );"
#     sed -i "/$init_string/r $WORDPRESS_SOURCE/permalink-settings.txt" $WORDPRESS_HOME/wp-settings.php
#     init_row=$(grep "$init_string" -n $WORDPRESS_HOME/wp-settings.php | head -n 1 | cut -d ":" -f1)
#     sed -i "${init_row}d" $WORDPRESS_HOME/wp-settings.php
# else
#     echo "INFO: Permalink setting is exist!"
# fi

echo "Setup openrc ..." && openrc && touch /run/openrc/softlevel

# setup server root
if [ ! $AZURE_DETECTED ]; then 
    echo "INFO: NOT in Azure, chown for "$WORDPRESS_HOME 
    chown -R nginx:nginx $WORDPRESS_HOME
fi

echo "Starting Redis ..."
redis-server &

if [ ! $AZURE_DETECTED ]; then	
    echo "NOT in AZURE, Start crond, log rotate..."	
    crond	
fi 

test ! -d "$SUPERVISOR_LOG_DIR" && echo "INFO: $SUPERVISOR_LOG_DIR not found. creating ..." && mkdir -p "$SUPERVISOR_LOG_DIR"
test ! -d "$NGINX_LOG_DIR" && echo "INFO: Log folder for nginx/php not found. creating..." && mkdir -p "$NGINX_LOG_DIR"
test ! -e /home/50x.html && echo "INFO: 50x file not found. createing..." && cp /usr/share/nginx/html/50x.html /home/50x.html
test -d "/home/etc/nginx" && echo "/home/etc/nginx exists.." && ln -s /home/etc/nginx /etc/nginx && ln -sf /usr/lib/nginx/modules /home/etc/nginx/modules
test ! -d "/home/etc/nginx" && mkdir -p /home/etc && cp -R /etc/nginx /home/etc/ && rm -rf /etc/nginx && ln -s /home/etc/nginx /etc/nginx && ln -sf /usr/lib/nginx/modules /home/etc/nginx/modules

#Updating php configuration values
if [[ -e $PHP_CUSTOM_CONF_FILE ]]; then
    echo "INFO: Updating PHP configurations..."
    update_php_config $PHP_CUSTOM_CONF_FILE "file_uploads" $FILE_UPLOADS "TOGGLE"
    update_php_config $PHP_CUSTOM_CONF_FILE "memory_limit" $PHP_MEMORY_LIMIT "MEM" $UB_PHP_MEMORY_LIMIT
    update_php_config $PHP_CUSTOM_CONF_FILE "upload_max_filesize" $UPLOAD_MAX_FILESIZE "MEM" $UB_UPLOAD_MAX_FILESIZE
    update_php_config $PHP_CUSTOM_CONF_FILE "post_max_size" $POST_MAX_SIZE "MEM" $UB_POST_MAX_SIZE
    update_php_config $PHP_CUSTOM_CONF_FILE "max_execution_time" $MAX_EXECUTION_TIME "NUM" $UB_MAX_EXECUTION_TIME
    update_php_config $PHP_CUSTOM_CONF_FILE "max_input_time" $MAX_INPUT_TIME "NUM" $UB_MAX_INPUT_TIME
    update_php_config $PHP_CUSTOM_CONF_FILE "max_input_vars" $MAX_INPUT_VARS "NUM" $UB_MAX_INPUT_VARS
fi

echo "INFO: creating /run/php/php-fpm.sock ..."
test -e /run/php/php-fpm.sock && rm -f /run/php/php-fpm.sock
mkdir -p /run/php
touch /run/php/php-fpm.sock
chown nginx:nginx /run/php/php-fpm.sock
chmod 777 /run/php/php-fpm.sock

sed -i "s/SSH_PORT/$SSH_PORT/g" /etc/ssh/sshd_config
echo "Starting SSH ..."
echo "Starting php-fpm ..."
echo "Starting Nginx ..."

cd /usr/bin/
supervisord -c /etc/supervisord.conf

