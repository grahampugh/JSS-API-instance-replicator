Icons
=====

To ascertain what icon a policy has, you need something like these commands:


```bash
icon_filename=$( curl -s -k https://$myserver/$instance/JSSResource/policies/id/$id/subset/self_service -H "Accept: application/xml" --user "$apiuser:$apiapassword" | xmllint --format - | grep '<filename>' | awk -F '<filename>|</filename>' '/<filename>/ {print $2}' | tr -d ' ' )

icon_id=$( curl -s -k https://$myserver/$instance/JSSResource/policies/id/$id/subset/self_service -H "Accept: application/xml" --user "$apiuser:$apiapassword" | xmllint --format -  | sed '/<category>/,/<\/category>/d' | awk -F '<id>|</id>' '/<id>/ {print $2}' | tr -d ' ' )
```

If you're looking for an existing icon to populate a new policy, you would need to trawl through all existing policies and write the results to some sort of array, which you can then do a search on filename to create an XML snippet containing something like:

```
    <self_service_icon>
      <id>$icon_id</id>
      <filename>$icon_filename</filename>
      <uri>https://server/instance/iconservlet/?id=$icon_id</uri>
    </self_service_icon>
```

Then, perhaps, you could use a `curl -X PUT` command to populate a policy with this information (although I don't think this even works!).

Upload an icon file:
```
curl -s -f -k -u "apiuser:$apipassword"  -X POST -F name=@"$icon_file" "$myserver/$instance/JSSResource/fileuploads/policies/id/$id"
```
