#!/bin/bash

# Script to either save JSS config via api to XML or upload that XML to a new JSS
#
# Original Author : richard@richard-purves.com
#
# Loosely based on the work by Jeffrey Compton at
# https://github.com/igeekjsc/JSSAPIScripts/blob/master/jssMigrationUtility.bash
#
# Adapted by Graham Pugh

# Version 0.1 - readwipe and writebk lists separated into files for clarity.
#               Parameters can now be commented out.
#				Option to provide config in a private separate file added.
#				Various changes to curl commands made as they didn't seem to work for me (maybe RedHat-related).
#				Changed name from JSS-Config-In-A-Box to JSS-API-Instance-Replicator to clarify that this only does API stuff.

# Set up variables here
export xmlloc_default="$HOME/Desktop/JSS_Config"
export origjssaddress_default="https://myserver"
export destjssaddress_default="https://myotherserver"
export origjssapiuser_default="JSS_config_download"
export destjssapiuser_default="JSS_config_write"
export origjssinstance_default="source"
export destjssinstance_default="dest01"

# This script relies on the following files, which contain a list of all the API parameters.
# Each parameter can be commented in or out, depending on what you wish to copy.
# Note that two files are necessary because the order has to be slightly different for reading and writing.
readwipefile="./readwipe.txt"
writebkfile="./writebk.txt"

# If you wish to store your confidential config in a separate file, specify it here to overwrite the above values.
# The name jciab-conf.sh is by default excluded in .gitignore so that your private data isn't made public:
configFile="./jciab-conf.sh"

### No need to edit below here

# Reset the internal counter
export resultInt=1

# Read in the variables from the configFile if it exists.
if [[ -f "$configFile" ]]; then
	. "$configFile"
fi

# These are the categories we're going to save or wipe
rwi=0
declare -a readwipe
while read -r line; do
	if [[ ${line:0:1} != '#' && $line ]]; then
		readwipe[$rwi]="$line"
		rwi=$((rwi+1))
	fi
done < $readwipefile

# These are the categories we're going to upload. Ordering is different from read/wipe.
wbi=0
declare -a writebk
while read -r line; do
	if [[ ${line:0:1} != '#' && $line ]]; then
		writebk[$wbi]="$line"
		wbi=$((wbi+1))
	fi
done < $writebkfile

# Start functions here
doesxmlfolderexist() {
	# Where shall we store all this lovely xml?
	echo -e "\nPlease enter the path to store data"
	read -p "(Or enter to use $HOME/Desktop/JSS_Config) : " xmlloc

	# Check for the skip
	if [[ $path = "" ]];
	then
		export xmlloc="$xmlloc_default"
	fi

	# Check and create the JSS xml folder and archive folders if missing.
	if [ ! -d "$xmlloc" ];
	then
		mkdir -p "$xmlloc"
		mkdir -p "$xmlloc"/archives
	else
		echo -e "\n"
		read -p "Do you wish to archive existing xml files? (Y/N) : " archive
		if [[ "$archive" = "y" ]] || [[ "$archive" = "Y" ]];
		then
			archive="YES"
		else
			archive="NO"
		fi
	fi

	# Check for existing items, archiving if necessary.
	for (( loop=0; loop<${#readwipe[@]}; loop++ ))
	do
		if [ "$archive" = "YES" ];
		then
			if [ $(ls -1 "$xmlloc"/"${readwipe[$loop]}"/* 2>/dev/null | wc -l) -gt 0 ];
			then
				echo "Archiving category: "${readwipe[$loop]}
				ditto -ck "$xmlloc"/"${readwipe[$loop]}" "$xmlloc"/archives/"${readwipe[$loop]}"-$( date +%Y%m%d%H%M%S ).zip
				rm -rf "$xmlloc/${readwipe[$loop]}"
			fi
		fi

	# Check and create the JSS xml resource folders if missing.
		if [ ! -f "$xmlloc/${readwipe[$loop]}" ];
		then
			mkdir -p "$xmlloc/${readwipe[$loop]}"
			mkdir -p "$xmlloc/${readwipe[$loop]}/id_list"
			mkdir -p "$xmlloc/${readwipe[$loop]}/fetched_xml"
			mkdir -p "$xmlloc/${readwipe[$loop]}/parsed_xml"
		fi
	done
}

grabexistingjssxml()
{
	# Setting IFS Env to only use new lines as field seperator
	OIFS=$IFS
	IFS=$'\n'

	# Loop around the array of JSS categories we set up earlier.
	for (( loop=0; loop<${#readwipe[@]}; loop++ ))
	do
		# Set our result incremental variable to 1
		export resultInt=1

		# Work out where things are going to be stored on this loop
		export formattedList=$xmlloc/${readwipe[$loop]}/id_list/formattedList.xml
		export plainList=$xmlloc/${readwipe[$loop]}/id_list/plainList
		export plainListAccountsUsers=$xmlloc/${readwipe[$loop]}/id_list/plainListAccountsUsers
		export plainListAccountsGroups=$xmlloc/${readwipe[$loop]}/id_list/plainListAccountsGroups
		export fetchedResult=$xmlloc/${readwipe[$loop]}/fetched_xml/result"$resultInt".xml
		export fetchedResultAccountsUsers=$xmlloc/${readwipe[$loop]}/fetched_xml/userResult"$resultInt".xml
		export fetchedResultAccountsGroups=$xmlloc/${readwipe[$loop]}/fetched_xml/groupResult"$resultInt".xml

		# Grab all existing ID's for the current category we're processing
		echo -e "\n\nCreating ID list for ${readwipe[$loop]} on template JSS \n"
		# echo -e "using $origjssaddress$jssinstance/JSSResource/${readwipe[$loop]} with user $origjssapiuser:$origjssapipwd"
		curl -s -k $origjssaddress$jssinstance/JSSResource/${readwipe[$loop]} -H "Accept: application/xml" --user "$origjssapiuser:$origjssapipwd" | xmllint --format - > $formattedList

		if [ ${readwipe[$loop]} = "accounts" ];
		then
			if [ $(cat "$formattedList" | grep "<users/>" | wc -l | awk '{ print $1 }') = "0" ];
			then
				echo "Creating plain list of user ID's..."
				cat $formattedList | sed '/<site>/,/<\/site>/d' | sed '/<groups>/,/<\/groups>/d' | awk -F '<id>|</id>' '/<id>/ {print $2}' > $plainListAccountsUsers
			else
				rm $formattedList
			fi

			if  [ $(cat "$formattedList" | grep "<groups/>" | wc -l | awk '{ print $1 }') = "0" ];
			then
				echo "Creating plain list of group ID's..."
				cat $formattedList | sed '/<site>/,/<\/site>/d'| sed '/<users>/,/<\/users>/d' | awk -F '<id>|</id>' '/<id>/ {print $2}' > $plainListAccountsGroups
			else
				rm $formattedList
			fi
		else
			if [ $(cat "$formattedList" | grep "<size>0" | wc -l | awk '{ print $1 }') = "0" ];
			then
				echo -e "\n\nCreating a plain list of ${readwipe[$loop]} ID's \n"
				cat $formattedList |awk -F'<id>|</id>' '/<id>/ {print $2}' > $plainList
			else
				rm $formattedList
			fi
		fi

		# Work out how many ID's are present IF formattedlist is present. Grab and download each one for the specific search we're doing. Special code for accounts because the API is annoyingly different from the rest.
		if [ $(ls -1 "$xmlloc/${readwipe[$loop]}/id_list"/* 2>/dev/null | wc -l) -gt 0 ];
		then
			case "${readwipe[$loop]}" in
				accounts)
					totalFetchedIDsUsers=$( cat "$plainListAccountsUsers" | wc -l | sed -e 's/^[ \t]*//' )
					for userID in $( cat $plainListAccountsUsers )
					do
						echo "Downloading User ID number $userID ( $resultInt out of $totalFetchedIDsUsers )"
						fetchedResultAccountsUsers=$( curl -s -k $origjssaddress/JSSResource/${readwipe[$loop]}/userid/$userID -H "Accept: application/xml" --user "$origjssapiuser:$origjssapipwd"  | xmllint --format - )
						itemID=$( echo "$fetchedResultAccountsUsers" | grep "<id>" | awk -F '<id>|</id>' '{ print $2; exit; }')
						itemName=$( echo "$fetchedResultAccountsUsers" | grep "<name>" | awk -F '<name>|</name>' '{ print $2; exit; }')
						cleanedName=$( echo "$itemName" | sed 's/[:\/\\]//g' )
						fileName="$cleanedName [ID $itemID]"
						echo "$fetchedResultAccountsUsers" > $xmlloc/${readwipe[$loop]}/fetched_xml/user_"$resultInt.xml"

						resultInt=$((resultInt + 1))
					done

					resultInt=1

					totalFetchedIDsGroups=$( cat "$plainListAccountsGroups" | wc -l | sed -e 's/^[ \t]*//' )
					for groupID in $( cat $plainListAccountsGroups )
					do
						echo "Downloading Group ID number $groupID ( $resultInt out of $totalFetchedIDsGroups )"
						fetchedResultAccountsGroups=$( curl -s -k $origjssaddress/JSSResource/${readwipe[$loop]}/groupid/$groupID -H "Accept: application/xml" --user "$origjssapiuser:$origjssapipwd"  | xmllint --format - )
						itemID=$( echo "$fetchedResultAccountsGroups" | grep "<id>" | awk -F '<id>|</id>' '{ print $2; exit; }')
						itemName=$( echo "$fetchedResultAccountsGroups" | grep "<name>" | awk -F '<name>|</name>' '{ print $2; exit; }')
						cleanedName=$( echo "$itemName" | sed 's/[:\/\\]//g' )
						fileName="$cleanedName [ID $itemID]"
						echo "$fetchedResultAccountsGroups" > $xmlloc/${readwipe[$loop]}/fetched_xml/group_"$resultInt.xml"

						resultInt=$((resultInt + 1))
					done
				;;

				*)
					totalFetchedIDs=$(cat "$plainList" | wc -l | sed -e 's/^[ \t]*//')

					for apiID in $(cat $plainList)
					do
						echo "Downloading ID number $apiID ( $resultInt out of $totalFetchedIDs )"

						curl -s -k $origjssaddress$jssinstance/JSSResource/${readwipe[$loop]}/id/$apiID -H "Accept: application/xml" --user "$origjssapiuser:$origjssapipwd" | xmllint --format - > $fetchedResult

						resultInt=$((resultInt + 1))
						fetchedResult=$xmlloc/${readwipe[$loop]}/fetched_xml/result"$resultInt".xml
					done
				;;
			esac

			# Depending which category we're dealing with, parse the grabbed files into something we can upload later.
			case "${readwipe[$loop]}" in
				computergroups)
					echo -e "\nParsing JSS computer groups"

					for resourceXML in $(ls $xmlloc/${readwipe[$loop]}/fetched_xml)
					do
						echo "Parsing computer group: $resourceXML"

						if [[ $(cat $xmlloc/${readwipe[$loop]}/fetched_xml/$resourceXML | grep "<is_smart>false</is_smart>") ]]
						then
							echo "$resourceXML is a static computer group"
							cat $xmlloc/${readwipe[$loop]}/fetched_xml/$resourceXML | grep -v "<id>" | sed '/<computers>/,/<\/computers/d' > $xmlloc/${readwipe[$loop]}/parsed_xml/static_group_parsed_"$resourceXML"
						else
							echo "$resourceXML is a smart computer group..."
							cat $xmlloc/${readwipe[$loop]}/fetched_xml/$resourceXML | grep -v "<id>" | sed '/<computers>/,/<\/computers/d' > $xmlloc/${readwipe[$loop]}/parsed_xml/smart_group_parsed_"$resourceXML"
						fi
					done
				;;

				policies|restrictedsoftware)
					echo -e "\nParsing ${readwipe[$loop]}"

					for resourceXML in $(ls $xmlloc/${readwipe[$loop]}/fetched_xml)
					do
						echo "Parsing policy: $resourceXML"

						if [[ $(cat $xmlloc/${readwipe[$loop]}/fetched_xml/$resourceXML | grep "<name>No category assigned</name>") ]]
						then
							echo "Policy $resourceXML is not assigned to a category. Ignoring."
						else
							echo "Processing policy file $resourceXML ."
							cat $xmlloc/${readwipe[$loop]}/fetched_xml/$resourceXML | grep -v "<id>" | sed '/<computers>/,/<\/computers>/d' | sed '/<self_service_icon>/,/<\/self_service_icon>/d' | sed '/<limit_to_users>/,/<\/limit_to_users>/d' | sed '/<users>/,/<\/users>/d' | sed '/<user_groups>/,/<\/user_groups>/d' > $xmlloc/${readwipe[$loop]}/parsed_xml/parsed_"$resourceXML"
						fi
					done
				;;

				*)
					echo -e "\nNo special parsing needed for: ${readwipe[$loop]}. Removing references to ID's\n"

					for resourceXML in $(ls $xmlloc/${readwipe[$loop]}/fetched_xml)
					do
						echo "Parsing $resourceXML"
						cat $xmlloc/${readwipe[$loop]}/fetched_xml/$resourceXML | grep -v "<id>" > $xmlloc/${readwipe[$loop]}/parsed_xml/parsed_"$resourceXML"
					done
				;;
			esac
		else
			echo -e "\nResource ${readwipe[$loop]} empty. Skipping."
		fi
	done

	# Setting IFS back to default
	IFS=$OIFS
}

wipejss()
{
	# Setting IFS Env to only use new lines as field seperator
	OIFS=$IFS
	IFS=$'\n'

	# THIS IS YOUR LAST CHANCE TO PUSH THE CANCELLATION BUTTON

	echo -e "\nThis action will erase the destination JSS before upload."
	echo "Are you utterly sure you want to do this?"
	read -p "(Default is NO. Type YES to go ahead) : " arewesure

	# Check for the skip
	if [[ $arewesure != "YES" ]];
	then
		echo "Ok, quitting."
		exit 0
	fi

	# OK DO IT

	for (( loop=0; loop<${#readwipe[@]}; loop++ ))
	do
		if [ ${readwipe[$loop]} = "accounts" ];
		then
			echo -e "\nSkipping ${readwipe[$loop]} category. Or we can't get back in!"
		else
			# Set our result incremental variable to 1
			export resultInt=1

			# Grab all existing ID's for the current category we're processing
			echo -e "\n\nProcessing ID list for ${readwipe[$loop]}\n"

			curl -s -k $destjssaddress$jssinstance/JSSResource/${readwipe[$loop]} -H "Accept: application/xml" --user "$destjssapiuser:$destjssapipwd" | xmllint --format - > /tmp/unprocessedid

			# Check if any ids have been captured. Skip if none present.
			check=$( echo /tmp/unprocessedid | grep "<size>0</size>" | wc -l | awk '{ print $1 }' )

			if [ "$check" = "0" ];
			then
				# What are we deleting?
				echo -e "\nDeleting ${readwipe[$loop]}"

				# Process all the item id numbers
				cat /tmp/unprocessedid | awk -F'<id>|</id>' '/<id>/ {print $2}' > /tmp/processedid

				# Delete all the item id numbers
				totalFetchedIDs=$( cat /tmp/processedid | wc -l | sed -e 's/^[ \t]*//' )

				for apiID in $(cat /tmp/processedid)
				do
					echo "Deleting ID number $apiID ( $resultInt out of $totalFetchedIDs )"
					curl -k $destjssaddress$jssinstance/JSSResource/${readwipe[$loop]}/id/$apiID -H "Accept: application/xml" --request DELETE --user "$destjssapiuser:$destjssapipwd"

					# curl -s -k --user "$jssapiuser:$jssapipwd" -H "Accept: application/xml" -X DELETE "$jssaddress$jssinstance/JSSResource/${readwipe[$loop]}/id/$apiID"
					resultInt=$((resultInt + 1))
				done
			else
				echo -e "\nCategory ${readwipe[$loop]} is empty. Skipping."
			fi
		fi
	done

	# Setting IFS back to default
	IFS=$OIFS

}

puttonewjss()
{
	# Setting IFS Env to only use new lines as field seperator
	OIFS=$IFS
	IFS=$'\n'

	echo -e "Writing to $jssinstance"

	for (( loop=0; loop<${#writebk[@]}; loop++ ))
	do
		if [ $(ls -1 "$xmlloc"/"${writebk[$loop]}"/parsed_xml/* 2>/dev/null | wc -l) -gt 0 ];
		then
			# Set our result incremental variable to 1
			export resultInt=1

			echo -e "\n\nPosting ${writebk[$loop]} to new JSS instance: $destjssaddress$jssinstance"

			case "${writebk[$loop]}" in
				accounts)
					echo -e "\nPosting user accounts."

					totalParsedResourceXML_user=$( ls $xmlloc/${writebk[$loop]}/parsed_xml/*user* | wc -l | sed -e 's/^[ \t]*//' )
					postInt_user=0

					for xmlPost_user in $(ls -1 $xmlloc/${writebk[$loop]}/parsed_xml/*user*)
					do
						let "postInt_user = $postInt_user + 1"
						echo -e "\nPosting $xmlPost_user ( $postInt_user out of $totalParsedResourceXML_user )"

						curl -s -k -i -H "Content-Type: application/xml" -d @"$xmlPost_user" --user "$destjssapiuser:$destjssapipwd" $destjssaddress$jssinstance/JSSResource/accounts/userid/0

					done

					echo -e "\nPosting user group accounts."

					totalParsedResourceXML_group=$( ls $xmlloc/${writebk[$loop]}/parsed_xml/*group* | wc -l | sed -e 's/^[ \t]*//' )
					postInt_group=0

					for xmlPost_group in $(ls -1 $xmlloc/${writebk[$loop]}/parsed_xml/*group*)
					do
						let "postInt_group = $postInt_group + 1"
						echo -e "\nPosting $xmlPost_group ( $postInt_group out of $totalParsedResourceXML_group )"

						curl -s -k -i -H "Content-Type: application/xml" -d @"$xmlPost_group" --user "$destjssapiuser:$destjssapipwd" $destjssaddress$jssinstance/JSSResource/accounts/groupid/0

					done
				;;

				computergroups)
					echo -e "\nPosting static computer groups."

					totalParsedResourceXML_staticGroups=$(ls $xmlloc/${writebk[$loop]}/parsed_xml/static_group_parsed* | wc -l | sed -e 's/^[ \t]*//')
					postInt_static=0

					for parsedXML_static in $(ls -1 $xmlloc/${writebk[$loop]}/parsed_xml/static_group_parsed*)
					do
						let "postInt_static = $postInt_static + 1"
						echo -e "\nPosting $parsedXML_static ( $postInt_static out of $totalParsedResourceXML_staticGroups )"

						curl -s -k -i -H "Content-Type: application/xml" -d @"$parsedXML_static" --user "$destjssapiuser:$destjssapipwd" $destjssaddress$jssinstance/JSSResource/${writebk[$loop]}/id/0

					done

					echo -e "\nPosting smart computer groups"

					totalParsedResourceXML_smartGroups=$(ls $xmlloc/${writebk[$loop]}/parsed_xml/smart_group_parsed* | wc -l | sed -e 's/^[ \t]*//')
					postInt_smart=0

					for parsedXML_smart in $(ls -1 $xmlloc/${writebk[$loop]}/parsed_xml/smart_group_parsed*)
					do
						let "postInt_smart = $postInt_smart + 1"
						echo -e "\nPosting $parsedXML_smart ( $postInt_smart out of $totalParsedResourceXML_smartGroups )"

						curl -s -k -i -H "Content-Type: application/xml" -d @"$parsedXML_smart" --user "$destjssapiuser:$destjssapipwd" $destjssaddress$jssinstance/JSSResource/${writebk[$loop]}/id/0

					done
				;;

				*)
					totalParsedResourceXML=$(ls $xmlloc/${writebk[$loop]}/parsed_xml | wc -l | sed -e 's/^[ \t]*//')
					postInt=0

					for parsedXML in $(ls $xmlloc/${writebk[$loop]}/parsed_xml)
					do
						let "postInt = $postInt + 1"
						echo -e "\nPosting $parsedXML ( $postInt out of $totalParsedResourceXML )"

						echo -e <<END
						curl -sS -k -i -H "Content-Type: application/xml" --form file=@"$xmlloc/${writebk[$loop]}/parsed_xml/$parsedXML" --user "$destjssapiuser:$destjssapipwd" $destjssaddress$jssinstance/JSSResource/${writebk[$loop]}/id/0
END

						curl -s -k -i -H "Content-Type: application/xml" -d @"$xmlloc/${writebk[$loop]}/parsed_xml/$parsedXML" --user "$destjssapiuser:$destjssapipwd" $destjssaddress$jssinstance/JSSResource/${writebk[$loop]}/id/0

					done
				;;
			esac
		else
			echo -e "\nResource ${writebk[$loop]} empty. Skipping."
		fi
	done

	# Setting IFS back to default
	IFS=$OIFS
}

MainMenu()
{
	# Set IFS to only use new lines as field separator.
	OIFS=$IFS
	IFS=$'\n'

	while [[ $choice != "q" ]]
	do
		echo -e "\nMain Menu"
		echo -e "=========\n"
		echo -e "1) Download config from original JSS"
		echo -e "2) Upload config to new JSS instance"

		echo -e "q) Quit!\n"

		read -p "Choose an option (1-2 / q) : " choice

		case "$choice" in
			1)
				echo -e "\n"
				read -p "Enter the originating JSS server address (or enter for $origjssaddress_default) : " jssaddress
				read -p "Enter the originating JSS server api username (or enter for $origjssapiuser_default) : " jssapiuser
				read -p "Enter the originating JSS api user password : " -s jssapipwd

				# Read in defaults if not entered
				if [[ -z $jssaddress ]]; then
					jssaddress="$origjssaddress_default"
				fi
				if [[ -z $jssapiuser ]]; then
					jssapiuser="$origjssapiuser_default"
				fi

				export origjssaddress=$jssaddress
				export origjssapiuser=$jssapiuser
				export origjssapipwd=$jssapipwd

				# Ask which instance we need to process, check if it exists and go from there
				echo -e "\n"
				echo "Enter the originating JSS instance name from which to download API data (or enter for '$origjssinstance_default')"
				read -p "(Enter '/' for a non-context JSS) : " jssinstance

				# Check for the default or non-context
				if [[ $jssinstance == "/" ]]; then
					jssinstance=""
				elif [[ -z $jssinstance ]]; then
					jssinstance="/$origjssinstance_default"
				else
					jssinstance="/$jssinstance"
				fi

				grabexistingjssxml
			;;
			2)
				echo -e "\n"
				read -p "Enter the destination JSS server address (or enter for $destjssaddress_default) : " jssaddress
				read -p "Enter the destination JSS server api username (or enter for $destjssapiuser_default) : " jssapiuser
				read -p "Enter the destination JSS api user password : " -s jssapipwd

				# Read in defaults if not entered
				if [[ -z $jssaddress ]]; then
					jssaddress="$destjssaddress_default"
				fi
				if [[ -z $jssapiuser ]]; then
					jssapiuser="$destjssapiuser_default"
				fi

				export destjssaddress=$jssaddress
				export destjssapiuser=$jssapiuser
				export destjssapipwd=$jssapipwd

				# Ask which instance we need to process, check if it exists and go from there
				echo -e "\n"
				echo "Enter the destination JSS instance name to which to upload API data (or enter for '$destjssinstance_default')"
				read -p "(Enter '/' for a non-context JSS) : " jssinstance

				# Check for the default or non-context
				if [[ $jssinstance == "/" ]]; then
					jssinstance=""
				elif [[ -z $jssinstance ]]; then
					jssinstance="/$destjssinstance_default"
				else
					jssinstance="/$jssinstance"
				fi

				wipejss
				puttonewjss
			;;
			q)
				echo -e "\nThank you for using JSS Config in a Box!"
			;;
			*)
				echo -e "\nIncorrect input. Please try again."
			;;
		esac
	done

	# Setting IFS back to default
	IFS=$OIFS
}

# Start menu screen here
clear
echo -e "\n----------------------------------------"
echo -e "\n          JSS Config in a Box"
echo -e "\n----------------------------------------"
echo -e "    Version $currentver - $currentverdate"
echo -e "----------------------------------------\n"
echo -e "** Very Important Info **"
echo -e "\n1. Passwords WILL NOT be migrated with standard accounts. You must put these in again manually."
echo -e "2. Both macOS and iOS devices will NOT be migrated at all."
echo -e "3. Smart Computer Groups will only contain logic information."
echo -e "4. Static Computer groups will only contain name and site membership. Devices must be added manually."
echo -e "5. Distribution Point failover settings will NOT be included."
echo -e "6. Distribution Point passwords for Casper R/O and Casper R/W accounts will NOT be included."
echo -e "7. LDAP Authentication passwords will NOT be included."
echo -e "8. Directory Binding account passwords will NOT be included."
echo -e "9. Individual computers that are excluded from restricted software items WILL NOT be included in migration."
echo -e "10. Policies that are not assigned to a category will NOT be migrated."
echo -e "11. Policies that have Self Service icons and individual computers as a scope or exclusion will have these items missing."
echo -e "12. Policies with LDAP Users and Groups limitations will have these stripped before migration."

# Call functions to make this work here
doesxmlfolderexist
MainMenu

# All done!
exit 0
