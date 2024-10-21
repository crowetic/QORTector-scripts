#!/bin/bash

# Check if the bootstrap-archive.7z exists but db folder doesn't...

if [ -f "./bootstrap-archive.7z" ] && [ ! -d "./db"  ]; then
    echo "Extracting bootstrap archive as it was found, but db folder was not..."
    if ! command -v 7z &> /dev/null; then
        echo "7zip is not installed. Please install it using the following command:"
        echo "sudo apt update && sudo apt install p7zip-full"
        echo "Then, re-run this script."
        exit 1
    fi
    7z x bootstrap-archive.7z 
    mv bootstrap db 
    echo "Bootstrap extraction complete."
fi

# Check if the 'db' folder exists
if [ ! -d "./db" ] && [ ! -f "./bootstrap-archive.7z" ]; then
    echo "'db' folder and bootstrap-archive.7z do not exist. Downloading the Qortal bootstrap..."
    
    # Array of bootstrap URLs
    bootstrap_urls=(
        "https://bootstrap.qortal.org/bootstrap-archive.7z"
        "https://bootstrap2.qortal.org/bootstrap-archive.7z"
        "https://bootstrap3.qortal.org/bootstrap-archive.7z"
        "https://bootstrap4.qortal.org/bootstrap-archive.7z"
    )
    
    # Try downloading from each URL until successful
    for url in "${bootstrap_urls[@]}"; do
        echo "Trying to download from: $url"
        wget $url -O bootstrap-archive.7z
        if [ $? -eq 0 ]; then
            echo "Download successful."
            break
        else
            echo "Failed to download from $url. Trying the next URL..."
        fi
    done
    
    # Check if the download was successful
    if [ ! -f "./bootstrap-archive.7z" ]; then
        echo "All download attempts failed. Exiting script."
        exit 1
    fi
    
    # Check if 7zip is installed
    if ! command -v 7z &> /dev/null; then
        echo "7zip is not installed. Please install it using the following command:"
        echo "sudo apt update && sudo apt install p7zip-full"
        echo "Then, re-run this script."
        exit 1
    fi

    # Extract the archive if everything is ready
    echo "Extracting bootstrap archive..."
    7z x bootstrap-archive.7z 
    mv bootstrap db
    echo "Bootstrap extraction complete."
    
fi

echo "Checking Java installation..."

if command -v java &> /dev/null; then
    # Output the Java version
    java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
    echo "Java is installed. Version: $java_version"
else
    echo "Java is not installed."
    echo "Please install openjdk with the following command, then re-run this script..."
    echo "sudo apt update && sudo apt install openjdk-17-jre"
    exit 1
fi

echo "checking for lib folder and correct data..."
if [ ! -f "./lib/org/hsqldb/hsqldb/2.5.0-fixed/hsqldb-2.5.0-fixed.jar" ]; then
    echo "hsqldb tool not found, downloading copy from qortal cloud server..."
    wget https://cloud.qortal.org/s/zasfk3b8x8FnNKd/download/lib.zip
    echo "unzipping lib.zip..."
    unzip lib.zip
    echo "extraction complete"
    echo "Re-Checking for files..."
    
    if [ ! -f "./lib/org/hsqldb/hsqldb/2.5.0-fixed/hsqldb-2.5.0-fixed.jar" ]; then
        echo "something strange happened, please let the devs know!"
        exit 1
    fi 
    echo "check successful!"
fi

echo "starting hsqldb tool..."


java -cp  lib/org/hsqldb/hsqldb/2.5.0-fixed/hsqldb-2.5.0-fixed.jar org.hsqldb.util.DatabaseManagerSwing
