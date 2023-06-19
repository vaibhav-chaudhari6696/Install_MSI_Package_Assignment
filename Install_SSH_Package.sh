#!/bin/bash

# Checking for smbclient installed on local system   
if ! command -v smbclient &> /dev/null; then
    echo "Error: smbclient or samba-client (centos) is not installed. Please install it and try again."
    exit 1
fi

# Checking for nc installed on local system    
if ! command -v nc &> /dev/null; then
    echo "Error: nc is not installed. Please install it and try again."
    exit 1
fi


# Check if the public key file exists, if not generate new ssh key pair 
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "SSH Key pair not found,Generating SSH key pair..."
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    echo "SSH key pair generated."
fi


# Common Variables for remote Windows device details
install_dir='"C:\Program Files (x86)"'
port='"22"'
public_key="$(cat ~/.ssh/id_rsa.pub)"
public_key="\"$public_key\""



# Name of files on the local Linux device
winexe_binary_file="./winexe"
local_msi_file="./RWSSHDService_x64.msi"
local_ps_script="./msi_install.ps1"

# Define the path to the text file containing the list of devices
devices_file="./devices.txt"


# Name of files to save on the remote Windows device
remote_msi_file_name="RWSSHDService_x64.msi"
remote_ps_script_name="msi_install.ps1"




# Check if the MSI file exists
if [ ! -f "$local_msi_file" ]; then
    echo "The file $local_msi_file does not exist in the current directory."
    exit 1
fi

# Check if the PowerShell Script file exists
if [ ! -f "$local_ps_script" ]; then
    echo "The file $local_ps_script does not exist in the current directory."
    exit 1
fi

# Check if the winexe binary exists
if [ ! -f "$winexe_binary_file" ]; then
    echo "The winexe binary does not exist in the current directory."
    exit 1
fi


# Check if the devices file exists and is readable
if [ ! -f "$devices_file" ] || [ ! -r "$devices_file" ]; then
    echo "The devices file $devices_file is either missing or not readable."
    exit 1
fi


# Declare an array to store devices information from txt file
declare -a devices_list

# Read the devices file into the array
while IFS=$' \t,' read -r host username password folder || [ -n "$host" ]; do
    devices_list+=("$host" "$username" "$password" "$folder")
done < "$devices_file"



# Loop through the devices array
for ((i=0; i<${#devices_list[@]}; i+=4)); do

        host="${devices_list[$i]}"
        username="${devices_list[$i+1]}"
        password="${devices_list[$i+2]}"
        folder="${devices_list[$i+3]}"


        # Check if the IP address value present
        if ! [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || [ -z "$host" ] || [[ "$host" =~ [[:space:]] ]]; then
            echo "Error: Missing IP address, Skipping device"
            continue
        fi

        # Check if the username value present
        if [ -z "$username" ] || [[ "$username" =~ [[:space:]] ]]; then
            echo "Error: Missing username, Skipping device"
            continue
        fi

        # Check if the password  value present
        if [ -z "$password" ] || [[ "$password" =~ [[:space:]] ]]; then
            echo "Error: Missing password, Skipping device"
            continue
        fi

        # Check if the shared folder value present
        if [ -z "$folder" ]; then
            echo "Error: Missing folder path to copy MSI Package, Skipping device"
            continue
        fi



        echo -e "###########################################################################"
        echo "Machine"
        echo -e "$host"
        echo -e "###########################################################################\n"


        echo -e "------------ REACHABLE PORT CHECK ------------"

        # Check for port 445 open
        nc -z -w 10 "$host" "445"

        # If given port is not open on remote device then skip that device
        if [ "$?" -ne 0 ]; then
            echo "Machine $host is not reachable over port 445, skipping checks for machine"
            continue
        else
            echo "Machine $host is reachable over port 445"
        fi


        #Check the architecture of the remote Windows device using winexe
        arch_result=$(./winexe -U "$username%$password" //"$host" "wmic os get osarchitecture"  | awk 'NR==2')

        if [ $? -ne 0 ]; then
            echo "Error executing winexe command for device"
            echo "$arch_result"
            continue
        fi
        
        # Set Installation Directory according architecture of the remote Windows device
        if [[ $arch_result == *"64-bit"* ]]; then
            install_dir='"C:\Program Files (x86)"'
        else
            install_dir='"C:\Program Files"'
        fi


        # Get actual system path of shared folder, required to access MSI Package while installation  
        netshare_output=$(./winexe -U "$username%$password" //"$host" "net share $folder")

        if [ $? -ne 0 ]; then
            echo "Error executing winexe command for device"
            echo "$netshare_output"
            continue
        fi



        # Run the command and assign its output to folder_system_path
        folder_system_path=$(echo "$netshare_output" | sed -n 's/^Path\s*\(.*\)/\1/p')
        

        # Remove carriage return character
        folder_system_path=$(echo "$folder_system_path" | tr -d '\r')

        # Concatenate the path and filenames
        msi_package_path="${folder_system_path}\\${remote_msi_file_name}"
        msi_package_path="\"$msi_package_path\""

        ps_script_path="${folder_system_path}\\${remote_ps_script_name}"
        ps_script_path="\"$ps_script_path\""

        echo -e "\n"


        # Copy the Powershell Script file to the remote Windows device        
        if ! smbclient -U "$username%$password" "//${host}/$folder" -c "put "$local_ps_script" "$remote_ps_script_name""; then
            echo "Failed to copy $local_ps_script to $host"
            continue
        fi


        # Copy the SSH MSI file to the remote Windows device
        if ! smbclient -U "$username%$password" "//${host}/$folder" -c "put "$local_msi_file" "$remote_msi_file_name""; then
            echo "Failed to copy $local_msi_file to $host"
            continue
        fi


        echo -e "\n"
        

        # Execute the Powershell Script on the remote Windows device
        output=$(./winexe -U "$username%$password" //"$host" "powershell -ExecutionPolicy Bypass -File $ps_script_path  -Username $username -Password $password -Port $port -Publickey $public_key  -InstallDir $install_dir -PackagePath $msi_package_path")

        if [ $? -ne 0 ]; then
            echo "Error executing winexe command for device"
            echo "$output"
            continue
        fi

        echo "$output"

        
        echo -e "\n"

        ssh_known_host_path=$(echo ~/.ssh/known_hosts)
        ssh_path="\"$ssh_path\""
        ssh-keygen -f "$ssh_known_host_path" -R "$host"

        echo -e "\n\n"

        # Execute the SSH command to check the success of the connection
        ssh_output=$(ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes "$username@$host" "echo Success")   


        if [[ $ssh_output == *"Success"* ]]; then
            echo "SSH package installed successfully with all parameters on $host. "
        else
            echo "ERROR: SSH package is not installed successfully with all parameters on $host. OR Machine Not reachable over port 22"
        fi


        echo -e "----------------------------------------------------------------------------------"
        echo -e "----------------------------------------------------------------------------------\n\n\n"


done