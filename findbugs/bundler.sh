#! /bin/bash

function create_invoke_file {

    local filepath=$1

    cat > $filepath <<EOF
java
    -Xmx1024m
    -classpath <executable>
    -Dfindbugs.home="\${TOOL_DIR}/<tool-dir>"
    <main-class>
    -pluginList <plugin%:>
    -effort:<effort> 
    -exclude <exfile>
    -include <infile>
    -xml:withMessages
    -projectName <package-name-version>
    -output <assessment-report>
    -auxclasspath "<auxclasspath%:>:<bootclasspath%:>"
    -sourcepath <srcdir%:>
    -xargs
EOF
}

function create_tool_defaults_conf {

    local filepath=$1
    local plugins=$2

    cat > $filepath <<EOF    
effort=max
main-class=edu.umd.cs.findbugs.FindBugs2
EOF

    if [[ -n $plugins ]]; then
	echo "plugin=$plugins" >> $filepath
    fi

}

function md5 {
    (
	cd $1
	find . -type f ! -name md5sum -exec md5sum '{}' ';' > ./md5sum;
    )
}

function get_basedir {
    local archive=$1

    if [[ $archive == *.zip ]]; then
	zipinfo -1 $archive | sed -n -r 's@([ ^/]+)/.+@\1@p' | uniq
    elif [[ $archive == *.tar.gz ]]; then
	tar tf $archive | sed -n -r 's@([ ^/]+)/.+@\1@p' | uniq
    fi
}

function main {
    
    local out_dir="test"
    local tool_type=findbugs
    local tool_version="3.0.1"
    local tool_dir="$out_dir/$tool_type-$tool_version"
    local tool_archive="./existing/findbugs-noUpdateChecks-$tool_version.zip"

    mkdir -p $tool_dir/noarch/{in-files,swamp-conf}
    
    local tool_invoke_file="$tool_dir/noarch/in-files/tool-invoke.txt"
    create_invoke_file $tool_invoke_file

    local tool_defaults_conf="$tool_dir/noarch/in-files/tool-defaults.conf"
    create_tool_defaults_conf $tool_defaults_conf

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

    md5 $tool_dir
}

main $@
