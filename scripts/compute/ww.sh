#!/bin/bash

if [ $# -gt 0  ]; then
    input_type=$1
    case ${input_type} in 
        config)
            echo "xxxx"
            ;;
        check)
            echo "wwww"
            ;;
            *)
            echo "USAGE: $0 check|config" 
            ;;
    esac
else
    echo ":)"
fi
