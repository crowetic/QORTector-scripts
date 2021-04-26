#!/bin/sh
echo "stopping node.js for old UI"
killall -9 node*

echo "removing old files"
rm -R UI

echo "creating new UI folder and moving to that directory "

mkdir UI
cd UI

echo "cloning git repositories for Qortal UI"

git clone https://github.com/qortal/qortal-ui
git clone https://github.com/qortal/qortal-ui-core
git clone https://github.com/qortal/qortal-ui-crypto
git clone https://github.com/qortal/qortal-ui-plugins

cd qortal-ui

echo "installing dependencies and linking with yarn link for build process"

yarn install 

cd ../qortal-ui-core

yarn install
# Break any previous links
yarn unlink
yarn link

cd ../qortal-ui-crypto

yarn install 
# Break any previous links
yarn unlink
yarn link

cd ../qortal-ui-plugins

yarn install 
# Break any previous links
yarn unlink
yarn link

cd ../qortal-ui

yarn link qortal-ui-core 
yarn link qortal-ui-crypto 
yarn link qortal-ui-plugins

echo "starting build process...this may take a while...please be patient!"

yarn run build

echo "BUILD COMPLETE! You can now reboot the system to make use of the new UI!"
