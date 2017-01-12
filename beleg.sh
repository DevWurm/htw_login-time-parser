#!/bin/bash

# The scripts provides statistics about the total login time of a user on a specified host
# Params:
# 1: host - The host on which the statistics should be collected
# 2: user - The user for which the statistics should be collected
# [3: login_user - The user which should be used to login on the host]

# function for parsing a `last` output line into an interval of login beginning and login end seperated with '-'
parse_line() {
    line=$1

    beginning=$(date --date="$(echo $line | cut -d " " -f 4-8)" +%s) 
    end=$(date --date="$(echo $line | cut -d " " -f 10-14)" +%s) 

    echo "${beginning}-${end}"
}

# function for accessing the beginning part of an '-' seperated interval
beg() {
    echo $1 | cut -d '-' -f 1
}

# function for accessing the end part of an '-' seperated interval
end() {
    echo $1 | cut -d '-' -f 2
}

# function for calculating the curation of an '-' sperated interval
dur() {
    begt=$(beg $1)
    endt=$(end $1)
    echo $((endt-begt))
}

# function for generating usage statistics for a specific user from a wtmp file
create_stats() {
    file=$1
    user=$2

    res=0

    # storing the previously processed time interval in a variable to deduplicate overlapping intervals
    prev=""
    # note: when assigning the line to the variable, all consecutive whitespace will be truncated
    while read line
    do
        if [ "$prev" == "" ]
        then
            prev=$(parse_line "$line")
        else
            curr=$(parse_line "$line")

            if [ $(end $prev) -lt $(beg $curr) ]
            then
                # in this case the intervals are not overlapping and the last interval is added to the result
                durt=$(dur $prev)
                res=$((res+durt))
                prev=$curr
            elif [ $(end $prev) -lt $(end $curr) ]
            then
                # in this case the intervals are overlapping so they get merged
                prev="$(beg $prev)-$(end $curr)"
            else
                # in this case the current interval is completely in the last one, so we ignore it
                continue
            fi
        fi
    done < <(last -F -f $file $user | grep -v -e "down" -e "gone" -e "still" -e "crash" | tac | tail -n +3)
    # after looping, the last 'prev' value isn't handled, so it gets added to the result
    dur=$(dur $prev)
    res=$(($res + $dur))

    echo $res

    return 0
}

# function for printing text to stderr
echoerr() {
    (>&2 echo $1)
}

# function to print a time in seconds to days, hours, minutes, seconds 
print_time_formatted() {
    time=$1
    days=$((time/60/60/24))
    hours=$((time/60/60%24))
    minutes=$((time/60%60))
    seconds=$((time%60))

    echo "$days days, $hours hours, $minutes minutes, $seconds seconds"
}

# ensuring that required parameters are not empty
if [ -z ${1+x} ]
then
    echoerr "No host specified"
    exit 1
fi

if [ -z ${2+x} ]
then
    echoerr "No user specified"
    exit 2
fi

host=$1
user=$2

# optional login user, if the parameter is set, all ssh connections to the host are established with this user
login_user=$3

# testing connectivity to the provided host
echo "Testing availability of $host"
ping -c 1 -W 2 $host >/dev/null 2>/dev/null
if [ $? -ne 0 ]
then
    echoerr "Host $host is not reachable"
    exit 3
fi

# testing the existence of the user on the host
echo "Searching for $user@$host"
ssh ${login_user+"$login_user@"}$host "id $user" >/dev/null 2>/dev/null
if [ $? -ne 0 ]
then
    echoerr "User $user is not available on $host"
    exit 4
fi

# getting a temp file
tmp=$(mktemp)

echo "Downloading data from host"

# writing the content of all wtmp lofiles on the host in the temporary location
ssh ${login_user+"$login_user@"}$host "unxz --stdout /var/log/wtmp*.xz && exit" > $tmp 2>/dev/null
if [ $? -ne 0 ]
then
    echoerr "Couldn't download statistics from $host"
    exit 5
fi

ssh ${login_user+"$login_user@"}$host "cat /var/log/wtmp && exit" >> $tmp 2>/dev/null
if [ $? -ne 0 ]
then
    echoerr "Couldn't download statistics from $host"
    exit 6
fi

echo "Generating statistics"
logintime=$(create_stats $tmp $user)
echo "$logintime seconds"
print_time_formatted $logintime

# remove temp file
rm -rf $tmp >/dev/null 2>/dev/null

exit 0
