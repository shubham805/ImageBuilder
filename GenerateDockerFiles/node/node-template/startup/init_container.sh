#!/usr/bin/env bash
cat >/etc/motd <<EOL 
  _____                               
  /  _  \ __________ _________   ____  
 /  /_\  \\___   /  |  \_  __ \_/ __ \ 
/    |    \/    /|  |  /|  | \/\  ___/ 
\____|__  /_____ \____/ |__|    \___  >
        \/      \/                  \/ 
A P P   S E R V I C E   O N   L I N U X

Documentation: http://aka.ms/webapp-linux
NodeJS quickstart: https://aka.ms/node-qs
NodeJS Version : `node --version`
Note: Any data outside '/home' is not persisted

EOL
cat /etc/motd

mkdir "$PM2HOME"
chmod 777 "$PM2HOME"
ln -s /home/LogFiles "$PM2HOME"/logs

# Get environment variables to show up in SSH session
eval $(printenv | sed -n "s/^\([^=]\+\)=\(.*\)$/export \1=\2/p" | sed 's/"/\\\"/g' | sed '/=/s//="/' | sed 's/$/"/' >> /etc/profile)

# starting sshd process
source /opt/startup/startssh.sh

echo '' > /etc/cron.d/diag-cron
if [ "$WEBSITE_USE_DIAGNOSTIC_SERVER" != false ]; then
    /run-diag.sh > /dev/null
    echo '*/5 * * * * bash -l -c "/run-diag.sh > /dev/null"' >> /etc/cron.d/diag-cron
    chmod 0644 /etc/cron.d/diag-cron
    crontab /etc/cron.d/diag-cron
    /etc/init.d/cron start
fi

STARTUP_COMMAND_PATH="/opt/startup/startup.sh"
ORYX_ARGS="create-script -appPath /home/site/wwwroot -output $STARTUP_COMMAND_PATH -defaultApp=/opt/startup/default-static-site.js -userStartupCommand '$@'"

if [[ $APPSVC_REMOTE_DEBUGGING == "TRUE" ]]; then
    ORYX_ARGS="$ORYX_ARGS -remoteDebug -debugPort $APPSVC_TUNNEL_PORT"
elif [[ "$APPSVC_REMOTE_DEBUGGING_BREAK" == "TRUE" ]]; then
    ORYX_ARGS="$ORYX_ARGS -remoteDebugBrk -debugPort $APPSVC_TUNNEL_PORT"
fi

if [ -f "oryx-manifest.toml" ] && [[ "$APPSVC_RUN_ZIP" == "TRUE" ]]; then
    # NPM adds the current directory's node_modules/.bin folder to PATH before it runs, so commands in
    # "npm start" can files there. Since we move node_modules, we have to add it to the path ourselves.
    echo 'Fixing up path'
    export PATH=/node_modules/.bin:$PATH
    echo "$PATH"
fi

eval oryx $ORYX_ARGS

STARTUPCOMMAND=$(cat $STARTUP_COMMAND_PATH)
echo "Running $STARTUPCOMMAND"
exec $STARTUP_COMMAND_PATH
