#Configure CDN settings 
if [[ $IS_BLOB_STORAGE_ENABLED == "true" ]] && [ $(grep "BLOB_STORAGE_CONFIGURATION_COMPLETE" $WORDPRESS_LOCK_FILE) ]; then
    if wp w3-total-cache option set cdn.azure.cname $CDN_ENDPOINT --type=array --path=$WORDPRESS_HOME --allow-root \
    && wp w3-total-cache option set cdn.includes.enable true --type=boolean --path=$WORDPRESS_HOME --allow-root \
    && wp w3-total-cache option set cdn.minify.enable true --type=boolean --path=$WORDPRESS_HOME --allow-root \
    && wp w3-total-cache option set cdn.custom.enable true --type=boolean --path=$WORDPRESS_HOME --allow-root \
    && wp w3-total-cache option set cdn.theme.enable true --type=boolean --path=$WORDPRESS_HOME --allow-root; then
        echo "CDN_CONFIGURATION_COMPLETE" >> $WORDPRESS_LOCK_FILE
        #stop atd daemon
        service atd stop
    else
    	service atd start
        echo 'bash /usr/local/bin/w3tc_cdn_config.sh' | at now +5 minutes
    fi
elif [[ $IS_CDN_ENABLED == "true" ]]; then
    if wp w3-total-cache option set cdn.enabled true --type=boolean --path=$WORDPRESS_HOME --allow-root \
    && wp w3-total-cache option set cdn.engine "mirror" --path=$WORDPRESS_HOME --allow-root \
    && wp w3-total-cache option set cdn.mirror.domain $CDN_ENDPOINT --type=array --path=$WORDPRESS_HOME --allow-root; then
        echo "CDN_CONFIGURATION_COMPLETE" >> $WORDPRESS_LOCK_FILE
        #stop atd daemon
        service atd stop
    else
    	service atd start
        echo 'bash /usr/local/bin/w3tc_cdn_config.sh' | at now +5 minutes
    fi
else
    #stop atd daemon
    service atd stop
fi
