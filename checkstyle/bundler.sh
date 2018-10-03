#! /bin/bash

#set -x -v

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
	local silent_opt=
	#curl --silent --location --remote-name "$url"
	if egrep --quiet '^(http[ s]?|file|ftp)://' <(echo "$url"); then
	    echo "Downloading $url"
	else
	    echo "Copying $url"
	    silent_opt='--silent'
	fi
	curl $silent_opt --location --remote-name "$url"
    )
}

function create_invoke_file {

    local filepath=$1

    cat > $filepath <<EOF
java
    -Dcheckstyle.suppressions.file=<checkstyle-suppressions-file>
    -Dtranslation.severity=<translation-severity>
    -Dcheckstyle.header.file=<checkstyle-header-file>
    -Dcheckstyle.importcontrol.file=<checkstyle-importcontrol-file>
    -jar <executable>
    -f xml
    -o <assessment-report>
    -c <configuration-file>
    <srcfile% >
EOF
}

function create_tool_defaults_conf {

    local filepath="$1"
    local rule_set="$2"
    local suppress_set="$3"

    cat > "$filepath" <<EOF
translation-severity=error
checkstyle-header-file=\${TOOL_DIR}/<tool-dir>/java.header
checkstyle-importcontrol-file=\${TOOL_DIR}/<tool-dir>/import-control.xml
EOF

    [[ -f "$rule_set" ]] && echo "configuration-file=\${VMINPUTDIR}/$(basename $rule_set)" >> "$filepath"
    [[ -f "$suppress_set" ]] && echo "checkstyle-suppressions-file=\${VMINPUTDIR}/$(basename $suppress_set)" >> "$filepath"

}

function create_all {
    
    local tool_version="$1";
    local out_dir="$2";
    local tool_url="$3";
    local rule_set="$4"
    local tool_type=checkstyle
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

    local tool_invoke_file="$tool_dir/noarch/in-files/tool-invoke.txt"
    create_invoke_file "$tool_invoke_file"

    [[ -f "$rule_set" ]] && copy_file "$rule_set" "$tool_dir/noarch/in-files/"

    local suppress_set="$tool_dir/noarch/in-files/swamp_suppressions.xml"
cat > "$suppress_set" <<EOF
<?xml version="1.0"?>

<!DOCTYPE suppressions PUBLIC
    "-//Puppy Crawl//DTD Suppressions 1.1//EN"
    "http://www.puppycrawl.com/dtds/suppressions_1_1.dtd">

<suppressions>
</suppressions>
EOF

    local tool_defaults_conf="$tool_dir/noarch/in-files/tool-defaults.conf"
    create_tool_defaults_conf "$tool_defaults_conf" \
	"$tool_dir/noarch/in-files/swamp_checkstyle_checks.xml" \
	"$suppress_set"

    local tool_conf="$tool_dir/noarch/in-files/tool.conf"

    cat > $tool_conf <<EOF
tool-archive=$(basename $tool_archive)
tool-dir=$(get_basedir $tool_archive)
tool-invoke=$(basename $tool_invoke_file)
tool-defaults=$(basename $tool_defaults_conf)
tool-type=$tool_type
tool-version=$tool_version
executable=checkstyle-$tool_version-all.jar
supported-language-version=java-7 java-8
tool-language-version=java-8
EOF

    md5 "$tool_dir"
}

readonly USAGE_STR="
Usage:
  $0 [(-O|--outdir) <output-directory-path>]? [(-U|--url) <tool-archive-url]? [(-R|--ruleset-url) <ruleset-url>]* <version>

Optional arguments:
  [(-O|--outdir) <output-directory-path>]  : Path to the directory to create/copy files. Default is \$PWD
  [(-U|--url) <tool-archive-url] : URL for the tool, If the url starts with http(s), file is downloaded from the internet

Required arguments:
  [(-R|--ruleset) <ruleset-url>] : URL for a ruleset file
  <version> : Version number of the tool
"

function main {

    local version=
    local out_dir=
    local tool_url=
    local rule_set=

    if [[ $# -lt 1 ]]; then
	echo -e "$USAGE_STR"
	exit 1;
    fi

    while test $# -gt 0; do
	local key="$1"

	case "$key" in
	    (-U|--url)
            tool_url="$2"; 
	    shift; 
	    ;;
	    (-O|--outdir)
            out_dir="$2"; 
	    shift;
	    ;;
	    (-R|--ruleset)
            rule_set="$2"; 
	    shift; 
	    ;;
	    (-h|-H|--help)
            echo -e "$USAGE_STR";
	    exit 0;
	    ;;
	    (*)
	    if egrep --quiet '^[[:digit:]][.][[:digit:]]{1,2}([.][[:digit:]])?$' <(echo "$key"); then
		version="$key";
	    else
		rule_set="$key";
	    fi
	    ;;
	esac
	shift;
    done

    if [[ -z "$version" ]] ; then
	echo "Error: version number is a mandotry argument"
	echo -e "$USAGE_STR"
	exit 1
    fi

    if [[ -z "$rule_set" ]]; then
	echo "Error: ruleset url is a mandotry argument"
	echo -e "$USAGE_STR"
	exit 1
    fi

    tool_url="${tool_url:-http://sourceforge.net/projects/checkstyle/files/checkstyle/$version/checkstyle-$version-bin.zip}"
    out_dir="${out_dir:-$PWD}"

    echo create_all "$version" "$out_dir" "$tool_url" "$rule_set" 
    create_all "$version" "$out_dir" "$tool_url" "$rule_set" 
}

main $@
