#!/bin/bash

error_exit() {
    echo "$1" >&2
    exit 1
}

if ! command -v 7z &> /dev/null; then
    echo "\e[33m 7zip is not installed. !!-NOTICE-!! !!-USER INPUT REQUIRED-!! - Please read and answer the following question, then input sudo password if you choose to install 7zip! \e[0m"
    read -p "\e[34m Would you like to install it now? (y/n): \e[0m" install_response
    if [[ "$install_response" =~ ^[Yy]$ || "$install_response" =~ ^[Yy][Ee][Ss]$ ]]; then
        sudo apt update && sudo apt install -y p7zip-full || error_exit "\e[31m Failed to install 7zip. Please try installing it manually. \e[0m \e[34m utilize 'sudo apt update && sudo apt install p7zip-full' for ubuntu/debian machines. \e[0m"
    else
            error_exit "\e[31m 7zip is required to proceed. Exiting script. \e[0m"
    fi
fi

# Check for required software at the start

# Check for 7zip
if ! command -v 7z &> /dev/null; then
    echo "7zip is not installed. !!-NOTICE-!! !!-USER INPUT REQUIRED-!! - Please read and answer the following question, then input sudo password if you choose to install 7zip!"
    read -p "Would you like to install it now? (y/n): " install_response_7zip
    if [[ "$install_response_7zip" =~ ^[Yy]$ || "$install_response_7zip" =~ ^[Yy][Ee][Ss]$ ]]; then
        sudo apt update && sudo apt install -y p7zip-full || error_exit "Failed to install 7zip. Please try installing it manually. Utilize 'sudo apt update && sudo apt install p7zip-full' for Ubuntu/Debian machines."
    else
        error_exit "7zip is required to proceed. Exiting script."
    fi
fi

# Check for unzip
if ! command -v unzip &> /dev/null; then
    echo "unzip is not installed. !!-NOTICE-!! !!-USER INPUT REQUIRED-!! - Please read and answer the following question, then input sudo password if you choose to install unzip!"
    read -p "Would you like to install it now? (y/n): " install_response_unzip
    if [[ "$install_response_unzip" =~ ^[Yy]$ || "$install_response_unzip" =~ ^[Yy][Ee][Ss]$ ]]; then
        sudo apt update && sudo apt install -y unzip || error_exit "Failed to install unzip. Please try installing it manually. Utilize 'sudo apt update && sudo apt install unzip' for Ubuntu/Debian machines."
    else
        error_exit "unzip is required to proceed. Exiting script."
    fi
fi

# Check for Java
if ! command -v java &> /dev/null; then
    echo "Java is not installed. !!-NOTICE-!! !!-USER INPUT REQUIRED-!! - Please read and answer the following question, then input sudo password if you choose to install Java!"
    read -p "Would you like to install it now? (y/n): " install_response_java
    if [[ "$install_response_java" =~ ^[Yy]$ || "$install_response_java" =~ ^[Yy][Ee][Ss]$ ]]; then
        sudo apt update && sudo apt install -y openjdk-17-jre || error_exit "Failed to install Java. Please try installing it manually. Utilize 'sudo apt update && sudo apt install openjdk-17-jre' for Ubuntu/Debian machines."
    else
        error_exit "Java is required to proceed. Exiting script."
    fi
fi

# Check if the bootstrap-archive.7z exists but db folder doesn't...
if [ -f "./bootstrap-archive.7z" ] && [ ! -d "./db" ]; then
    echo "Extracting bootstrap archive as it was found, but db folder was not..."
    7z x bootstrap-archive.7z || error_exit "Failed to extract bootstrap archive."
    mv bootstrap db || error_exit "Failed to rename bootstrap directory."
    echo "\e[32m Bootstrap extraction complete. \e[0m"
fi

# Check if the 'db' folder exists
if [ ! -d "./db" ] && [ ! -f "./bootstrap-archive.7z" ]; then
    echo "\e[33m 'db' folder and bootstrap-archive.7z do not exist. \e[0m \e[34m Downloading the Qortal bootstrap... \e[0m"
    
    bootstrap_urls=(
        "https://bootstrap.qortal.org/bootstrap-archive.7z"
        "https://bootstrap2.qortal.org/bootstrap-archive.7z"
        "https://bootstrap3.qortal.org/bootstrap-archive.7z"
        "https://bootstrap4.qortal.org/bootstrap-archive.7z"
    )
    
    for url in "${bootstrap_urls[@]}"; do
        echo "Trying to download from: $url"
        curl -L -O $url
        if [ $? -eq 0 ]; then
            echo "Download successful."
            break
        else
            echo "\e[31m Failed to download \e[0m from \e[33m $url \e[0m. \e[34m Trying the next URL...\e[0m"
        fi
    done
    
    if [ ! -f "./bootstrap-archive.7z" ]; then
        error_exit "\e[31m All download attempts failed. Exiting script.\e[0m"
    fi

    echo "Extracting bootstrap archive..."
    7z x bootstrap-archive.7z || error_exit "Failed to extract bootstrap archive."
    mv bootstrap db || error_exit "Failed to rename bootstrap directory."
    echo "Bootstrap extraction complete."
fi

java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
echo "Java is installed. Version: $java_version"

echo "Checking for lib folder and correct data..."

# Check if lib.zip exists and extract if it does
if [ -f "./lib.zip" ]; then
    echo "lib.zip found. Extracting..."
    unzip -q lib.zip || error_exit "Failed to unzip lib.zip."
    echo "Extraction complete."
else
    echo "lib.zip not found. Downloading copy from qortal cloud server..."
    curl -L -O "https://cloud.qortal.org/s/zasfk3b8x8FnNKd/download/lib.zip" || error_exit "Failed to download lib.zip."
    echo "Download complete. Extracting lib.zip..."
    unzip -q lib.zip || error_exit "Failed to unzip lib.zip."
    echo "Extraction complete."
fi

# Re-check for required jar file
echo "Re-checking for required jar file..."
if [ ! -f "./lib/org/hsqldb/hsqldb/2.5.0-fixed/hsqldb-2.5.0-fixed.jar" ]; then
    error_exit "Something strange happened, hsqldb-2.5.0-fixed.jar was not found even though it should have been as it was already unzipped, please let the devs know!"
fi

echo "Check successful!"

# Create README file for hsqldb tool
if [ ! -f "./hsqldbtool-README.txt" ]; then
    echo "Creating README file for hsqldb tool..."
    cat <<EOL > hsqldbtool-README.txt
HSQLDBtool README:

To CONNECT to the Qortal db ... once the app is running, ensure the settings are set as shown: 

Type: HSQL Database Engine In-Memory
Driver: org.hsqldb.jdbc.JDBCDriver
URL: jdbc:hsqldb:file:db/blockchain
User: SA
Password: {leave_blank_there_is_NO_PASSWORD}

Be sure the user is SA, and password is nothing. Blank password as there isn't one. With the exact settings above you can open and play with the Qortal db with the db tool!
EOL
    
fi
echo "README file created successfully."

echo "Starting hsqldb tool..."


echo "Checking for lock file..."
if [ -f "db/blockchain.lck" ]; then
    echo "Lock file found. Removing it to prevent lock acquisition failure."
    rm -f db/blockchain.lck || error_exit "Failed to remove lock file. Please remove it manually and try again."
    echo "Lock file removed."
fi

echo "starting hsqldbtool..."
java -cp lib/org/hsqldb/hsqldb/2.5.0-fixed/hsqldb-2.5.0-fixed.jar org.hsqldb.util.DatabaseManagerSwing --url jdbc:hsqldb:file:db/blockchain --user SA

