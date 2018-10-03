#! /bin/bash

set -x -v

function md5 {
    (
	cd $1
	find . -type f ! -name md5sum -exec md5sum '{}' ';' > ./md5sum;
    )
}

function get_basedir {
    local archive="$1"

    if [[ "$archive" == *.zip ]]; then
	zipinfo -1 "$archive" | sed -n -r 's@([^/]+)/.+@\1@p' | uniq
    elif [[ "$archive" == *.tar.gz ]]; then
	tar tf "$archive" | sed -n -r 's@([^/]+)/.+@\1@p' | uniq
    fi
}

function copy_file {
    local url="$1"
    local dir="$2"

    if egrep --quiet --invert-match '^(http[s]?|file|ftp)://' <(echo "$url"); then
	url="file://$(readlink -e $url)"
    fi

    (
	cd "$dir"
	curl --silent --location --remote-name "$url"
    )
}

function create_invoke_file {

    local filepath=$1

    cat > $filepath <<EOF
java
    <max-heap>
    <min-stack>
    -classpath <executable>
    -Dfindbugs.home="\${TOOL_DIR}/<tool-dir>"
    <main-class>
    -pluginList <plugin>
    -effort:<effort> 
    -exclude <exclude-bugs>
    -include <include-bugs>
    -xml:withMessages
    -projectName <package-name-version>
    -output <assessment-report>
    -auxclasspath "<auxclasspath%:>:<bootclasspath%:>"
    -sourcepath <srcdir%:>
    -xargs
EOF
}

function create_tool_defaults_conf {

    local filepath="$1"
    local exclude="$2"
    local include="$3"
    local plugins="$4"

    cat > "$filepath" <<EOF
max-heap=-Xmx1024m
min-stack=-Xss2m
effort=max
main-class=edu.umd.cs.findbugs.FindBugs2
EOF

    [[ -f "$exclude" ]] && echo "exclude-bugs=\${VMINPUTDIR}/$(basename $exclude)" >> "$filepath"
    [[ -f "$include" ]] && echo "include-bugs=\${VMINPUTDIR}/$(basename $include)" >> "$filepath"
    [[ -n "$plugins" ]] && echo "plugin=$plugins" >> "$filepath"
}

function create_all {
    
    local tool_version="$1"; shift
    local out_dir="$1"; shift
    local tool_url="$1"; shift
    local exclude="$1"; shift
    local include="$1"; shift
    
    declare -a plugins
    plugins=($@)

    local tool_type=findbugs
    local tool_dir="$out_dir/$tool_type-$tool_version"


    if [[ -d "$tool_dir" ]]; then
	echo "Error: Tool directory already exists: $tool_dir";
	exit ;
    fi

    mkdir -p $tool_dir/noarch/{in-files,swamp-conf}

    copy_file "$tool_url" "$tool_dir/noarch/in-files"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
	echo "Error: copying $tool_url failed, exit code returne: $exit_code"
	exit 1;
    fi

    local tool_archive="$tool_dir/noarch/in-files/$(basename $tool_url)"

    [[ -f "$exclude" ]] && copy_file "$exclude" "$tool_dir/noarch/in-files"
    [[ -f "$include" ]] && copy_file "$include" "$tool_dir/noarch/in-files"

    declare -a valid_plugins
    for url in ${plugins[*]}; do
	copy_file $url  "$tool_dir/noarch/in-files"
	exit_code=$?
	if [[ $exit_code -ne 0 ]]; then
	    echo "Warning: copying $tool_url failed, exit code returne: $exit_code"
	else
	    valid_plugins[${#valid_plugins[*]}]="$(basename $url)"
	fi
    done

    local tool_invoke_file="$tool_dir/noarch/in-files/tool-invoke.txt"
    create_invoke_file $tool_invoke_file

    local tool_defaults_conf="$tool_dir/noarch/in-files/tool-defaults.conf"
    create_tool_defaults_conf $tool_defaults_conf \
	"$exclude" \
        "$include" \
	$(printf "\${VMINPUTDIR}/%s:" "${valid_plugins[@]}")

    local tool_conf="$tool_dir/noarch/in-files/tool.conf"

    cat > $tool_conf <<EOF
tool-archive=$(basename $tool_archive)
tool-dir=$(get_basedir $tool_archive)
tool-invoke=$(basename $tool_invoke_file)
tool-defaults=$(basename $tool_defaults_conf)
tool-type=$tool_type
tool-version=$tool_version
executable=lib/findbugs.jar
tool-use-input-file=yes
EOF

local supported_versions='java-7 java-8'
if egrep --quiet '^2.[0-9].[0-9]' <(echo "$tool_version") ; then
    supported_versions='java-7'
fi

echo "supported-language-version=$supported_versions" >> $tool_conf

    md5 $tool_dir
}

readonly USAGE_STR="
Usage:
  $0 [(-O|--outdir) <path-to-output-dir>]? [(-R|--url) <url-for-the-archive]? [(-P|--plugin) <url-for-plugin>]* <version>

Optional arguments:
  [(-O|--outdir) <path-to-output-dir>]  #Path to the directory to create/copy files. Default is \$PWD
  [(-R|--url) <url-for-the-archive] URL for the tool, If the url starts with http(s), file is downloaded from the internet
  [(-P|--plugin) <url-for-plugin>] URL for a plugin, multiple plugins can be specified
  [(-E|--exclude) <exclude-bugs-filepath>] File contains bug patters which must not be checked
  [(-I|--include) <include-bugs-filepath>] File contains bug patters which must be checked

Required arguments:
  <version> Version number of the tool
"

function main {

    local version=
    local out_dir=
    local tool_url=
    local exclude=false
    local include=false
    declare -a plugins

    if [[ $# -lt 1 ]]; then
	echo -e "$USAGE_STR"
	exit 1;
    fi

    while test $# -gt 0; do
	local arg="$1"

	case "$arg" in
	    (-R|--url)
            tool_url="$2"; 
	    shift; 
	    ;;
	    (-O|--outdir)
            out_dir="$2"; 
	    shift;
	    ;;
	    (-P|--plugin)
	    plugins[${#plugins[*]}]="$2"
	    shift;
	    ;;
	    (-E|--exclude)
            exclude="$2"; 
	    shift; 
	    ;;
	    (-I|--include)
            include="$2"; 
	    shift; 
	    ;;
	    (-h|-H|--help)
            echo -e "$USAGE_STR";
	    exit 0;
	    ;;
	    ([[:digit:]][.][[:digit:]][.][[:digit:]])
	    version="$arg";
	    ;;
	esac
	shift;
    done

    if [[ -z $version ]]; then
	echo "Error: Need a version number as argument"
	echo -e "$USAGE_STR"
	exit 1
    fi

    tool_url="${tool_url:-http://prdownloads.sourceforge.net/findbugs/findbugs-noUpdateChecks-$version.zip}"
    out_dir="${out_dir:-$PWD}"

    create_all "$version" "$out_dir" "$tool_url" \
	"$exclude" "$include" "${plugins[@]}"
}

main $@
