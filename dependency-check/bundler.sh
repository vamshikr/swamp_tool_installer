#! /bin/bash

set -x


function md5 {
    (
	    cd $1
	    find . -type f ! -name md5sum -exec md5sum '{}' ';' > ./md5sum;
    )
}

function get_basedir {
    local archive="$1"
    local extended_regex="-r"

    if [[ "$(uname -s | tr [[:upper:]] [[:lower:]] )" == "darwin" ]]; then
        extended_regex="-E"
    fi
    
    if [[ "$archive" == *.zip ]]; then
	    zipinfo -1 "$archive" | sed -n "$extended_regex" 's@([^/]+)/.+@\1@p' | uniq
    elif [[ "$archive" == *.tar.gz ]]; then
	    tar tf "$archive" | sed -n "$extended_regex" 's@([^/]+)/.+@\1@p' | uniq
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
<executable>
	--format ALL
	--noupdate
	--disableAssembly
	--disableAutoconf
	--disableBundleAudit
	--disableCmake
	--disableComposer
	--disableNodeJS
	--disableNuspec
	--disableOpenSSL
	--disablePyDist
	--disablePyPkg
	--disableRubygems
	--project <package-name-version>
	--out "\${RESULTS_DIR}"
	--scan <auxclasspath% --scan>
	--log "\${RESULTS_DIR}/assessment.log"
EOF
}

function create_tool_defaults_conf {

    local filepath="$1"
    
    cat > "$filepath" <<EOF
assessment-report-template=dependency-check-report.xml
EOF
}

function create_all {
    
    local tool_version="$1"; shift
    local out_dir="$1"; shift
    local tool_url="$1"; shift

    local tool_type="dependency-check"
    local tool_dir="$out_dir/$tool_type-$tool_version"

    

    if [[ -d "$tool_dir" ]]; then
	    echo "Error: Tool directory already exists: $tool_dir";
	    exit ;
    fi

    mkdir -p $tool_dir/noarch/{in-files,swamp-conf}
    local tool_archive="$tool_dir/noarch/in-files/$tool_type-$tool_version-release.zip"
    copy_file "$tool_url" "$tool_dir/noarch/in-files" "$(basename $tool_archive)"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
	    echo "Error: copying $tool_url failed, exit code returne: $exit_code"
	    exit 1;
    fi

    (
        cd "$tool_dir/noarch/in-files" && \
            unzip "$(basename $tool_archive)" && \
            
            (
                cd "$(get_basedir $tool_archive)" && \
                    ./bin/dependency-check.sh --updateonly
            ) && \
                zip -0 -r "$(basename $tool_archive)" "$(get_basedir $tool_archive)" && \
                rm -rf "$(get_basedir $tool_archive)"
    )
    
    local tool_defaults_conf="$tool_dir/noarch/in-files/tool-defaults.conf"
    create_tool_defaults_conf $tool_defaults_conf

    local tool_invoke_file="$tool_dir/noarch/in-files/tool-invoke.txt"
    create_invoke_file $tool_invoke_file

    local tool_archive_path="$tool_archive_dir"
    local tool_conf="$tool_dir/noarch/in-files/tool.conf"

    cat > $tool_conf <<EOF
tool-archive=$(basename $tool_archive)
tool-dir=$(get_basedir $tool_archive)
tool-invoke=$(basename $tool_invoke_file)
tool-defaults=$(basename $tool_defaults_conf)
tool-type=$tool_type
tool-version=$tool_version
executable=bin/dependency-check.sh
supported-language-version=java-7 java-8
tool-language-version=java-8
EOF

    md5 $tool_dir
}

readonly USAGE_STR="
Usage:
  $0 [(-O|--outdir) <path-to-output-dir>]? [(-R|--url) <url-for-the-archive]? [(-P|--plugin) <url-for-plugin>]* <version>

Optional arguments:
  [(-O|--outdir) <path-to-output-dir>]  #Path to the directory to create/copy files. Default is \$PWD
  [(-R|--url) <url-for-the-archive] URL for the tool, If the url starts with http(s), file is downloaded from the internet

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
