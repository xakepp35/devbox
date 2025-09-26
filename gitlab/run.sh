#!/bin/sh


# Generate password
generate_password(){
    local length=${1:-12}   # Default length 12 symbols
    # Generate password using /dev/urandom, base64, and tr to remove unwanted chars
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
    echo
}

password=$(generate_password 16)

echo $password