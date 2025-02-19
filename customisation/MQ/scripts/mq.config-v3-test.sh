#!/bin/bash
# the following url provides an elegant solution for getting the current path
# https://stackoverflow.com/questions/9889938/shell-script-current-directory
# DIR="$( cd "$( dirname "$0" )" && pwd )"
# By switching directories in a subshell, we can then call pwd and get the correct path of the script regardless of context.
# You can then use $DIR as "$DIR/path/to/file"

DIR="$( cd "$( dirname "$0" )" && pwd )/"
echo $DIR
exit 0