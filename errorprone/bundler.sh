#! /bin/bash


function get_bug_patterns {
    
        
    local BUG_PATTERN_URL="https://errorprone.info/bugpatterns"

    curl \
        --silent \
        --location \
        --remote-name "$BUG_PATTERN_URL" \
        --output "bugpatterns"
    
    sed -n -E '/<h2 id="on-by-default--error">On by default : ERROR<\/h2>/,/<h2 id="experimental--warning">Experimental : WARNING<\/h2>/ s@<p><strong><a href="[^"]+">(.+)</a></strong><br />@\1@p' "bugpatterns"
    
}

function md5sum { 
    md5 $1 | tr -d '()' | awk '{print $4, $2}'
}

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
    local filename="$3"
    
    if egrep --quiet --invert-match '^(http[s]?|file|ftp)://' <(echo "$url"); then
	    url="file://$(readlink -e $url)"
    fi

    (
	    cd "$dir"
        if [[ -n "$filename" ]]; then
            curl --silent --location --remote-name "$url"
	    else
            curl --silent --location --remote-name "$url" --output "$filename"
        fi
    )
}

function zipup {

    : "${1:?Takes a director as argument}";
    local delete=false;
    [[ $# -gt 1 ]] && [[ "$1" == "-d" ]] && delete=true && shift;
    local dirpath="$1";
    if test -d "$dirpath"; then
        local bname="$(basename $dirpath)";
        local tarball="$bname.zip";
        zip -q -0 -r "$tarball" "$bname";
        $delete && /bin/rm -rf "$dirpath";
    else
        echo "Error: $dirpath is not a directory ";
    fi
}


function create_invoke_file {

    local filepath=$1;shift
    
    cat > $filepath <<EOF
java 
	 -Xbootclasspath/"p:<bootclasspath%:>:<executable>"
	 -classpath <auxclasspath%:>
	 <main-class>
	 -XepIgnoreUnknownCheckNames
EOF
    
    for BUG_CODE in $@; do
        printf "\t-Xep:\"$BUG_CODE:WARN\"\n" >> $filepath
    done

    cat >> $filepath <<EOF
	 -implicit:none
	 -Xmaxerrs <max-errors>
	 -Xmaxwarns <max-errors>
 	 -target <target>
	 -source <source>
	 -encoding <encoding>
	 -sourcepath <srcdir%:>
	 -d <destdir>
	 "@<srcfile-filename>"
EOF
}

function create_tool_defaults_conf {

    local filepath="$1"
    
    cat > "$filepath" <<EOF
main-class=com.google.errorprone.ErrorProneCompiler
assessment-report-template=assessment_report{0}.out
max-errors=-1
EOF

}

function create_all {
    
    local tool_version="$1"; shift
    local out_dir="$1"; shift
    local tool_url="$1"; shift

    local tool_type="error-prone"
    local tool_dir="$out_dir/$tool_type-$tool_version"


    if [[ -d "$tool_dir" ]]; then
	    echo "Error: Tool directory already exists: $tool_dir";
	    exit ;
    fi

    mkdir -p $tool_dir/noarch/{in-files,swamp-conf}

    local tool_archive_dir="$tool_dir/noarch/in-files/$tool_type-$tool_version"
    mkdir -p "$tool_archive_dir"
    copy_file "$tool_url" "$tool_archive_dir"    
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
	    echo "Error: copying $tool_url failed, exit code returne: $exit_code"
	    exit 1;
    fi

    (
        cd "$(dirname $tool_archive_dir)"
        zipup -d "$(basename $tool_archive_dir)"
    )
    
    local tool_defaults_conf="$tool_dir/noarch/in-files/tool-defaults.conf"
    create_tool_defaults_conf $tool_defaults_conf

    local tool_invoke_file="$tool_dir/noarch/in-files/tool-invoke.txt"
    create_invoke_file $tool_invoke_file $(get_bug_patterns)

    local tool_archive_path="$tool_archive_dir"
    local tool_conf="$tool_dir/noarch/in-files/tool.conf"

    cat > $tool_conf <<EOF
tool-archive=$(basename $tool_archive_dir).zip
tool-dir=$(basename $tool_archive_dir)
tool-invoke=$(basename $tool_invoke_file)
tool-defaults=$(basename $tool_defaults_conf)
tool-type=$tool_type
tool-version=$tool_version
executable=error_prone_ant-$tool_version.jar
valid-exit-status=[01]
tool-report-exit-code=2
tool-report-exit-code-msg=(Source|Target) option 1.[345] is no longer supported. Use 1.6 or later
tool-report-exit-code-task-name=errorprone-javasource-compatibility
supported-language-version=java-7 java-8
tool-language-version=java-8
report-on-stderr=true
EOF

    md5 $tool_dir
}

readonly USAGE_STR="
Usage:
  $0 [(-O|--outdir) <path-to-output-dir>]? [(-R|--url) <url-for-the-archive]? [(-P|--plugin) <url-for-plugin>]* <version>

Optional arguments:
  [(-O|--outdir) <path-to-output-dir>]  #Path to the directory to create/copy files. Default is \$PWD
  [(-R|--url) <url-for-the-archive] URL for the tool ant jar, If the url starts with http(s), file is downloaded from the internet, download the version you want here https://mvnrepository.com/artifact/com.google.errorprone/error_prone_ant

Required arguments:
  <version> Version number of the tool
"


function main {

    local version=
    local out_dir=
    local tool_url=

    if [[ $# -lt 1 ]]; then
	    echo -e "$USAGE_STR"
	    exit 1;
    fi

    while [[ $# -gt 0 ]]; do
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
	        (-h|-H|--help)
                echo -e "$USAGE_STR";
	            exit 0;
	            ;;
	        ([[:digit:]][.][[:digit:]][.][[:digit:]]*)
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

    out_dir="${out_dir:-$PWD}"

    create_all "$version" "$out_dir" "$tool_url"
}

main "$@"
