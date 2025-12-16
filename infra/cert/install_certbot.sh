#!/usr/bin/env bash

index=1
os_type=$(grep 'PRETTY_NAME=' /etc/os-release | cut -d '=' -f 2 | tr -d '"')
echo -e "\nstep $index -- install certbot on ${os_type} "

index=$((index+1)) 
echo -e  "\nstep $index -- Install system dependencies "
if [[ "$os_type" =~ "Ubuntu"  ]]
then
    sudo apt install python3 python3-dev python3-venv libaugeas-dev gcc -y
else
	echo "The script is not supported on the current operating system."
	exit 1
fi


index=$((index+1)) 
echo -e  "\nstep $index -- Remove certbot-auto and any Certbot OS packages "
if [[ "$os_type" =~ "Ubuntu"  ]]
then
	sudo apt-get remove certbot -y
fi

index=$((index+1)) 
echo -e  "\nstep $index -- Set up a Python virtual environment "
sudo python3 -m venv /opt/certbot/

index=$((index+1)) 
echo -e  "\nstep $index -- Install Certbot "
sudo /opt/certbot/bin/pip install --upgrade pip


index=$((index+1)) 
echo -e  "\nstep $index -- Remove certbot-auto and any Certbot OS packages "
/opt/certbot/bin/pip install certbot certbot-nginx

index=$((index+1)) 
echo -e  "\nstep $index -- Prepare the Certbot command "
if [ -e /usr/bin/certbot ]
then
	sudo rm -f /usr/bin/certbot
fi
ln -s /opt/certbot/bin/certbot /usr/bin/certbot

index=$((index+1)) 
echo -e  "\nstep $index -- This is the end of install Certbot command"