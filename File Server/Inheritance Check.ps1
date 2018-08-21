#Enumerates folders with NTFS permissions that are not inherited.
#Specify root folder and desired tree depth.

$folders = dir "\\server\share" -Recurse -Directory -Depth 3

foreach ($folder in $folders) {
    $result = icacls $($folder.FullName)
    $NotInherited = $result[0..$($result.Count - 3)] | ? { $_ -notlike '*(I)*' }
    If ($NotInherited) {
        $folder.FullName
        $NotInherited
    }
}
