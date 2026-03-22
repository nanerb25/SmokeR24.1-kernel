#!/bin/bash

export ARCH="arm"
export KBUILD_BUILD_HOST=$(lsb_release -d | awk -F":"  '{print $2}' | sed -e 's/^[ \t]*//' | sed -r 's/[ ]+/-/g')
export KBUILD_BUILD_USER="nanerbs25"

clean_build=0
config="tegra12_android_defconfig"
dtb_name="tegra124-mocha.dtb"
dtb_only=0
kernel_name=$(git rev-parse --abbrev-ref HEAD)
cpus_count=$(grep -c ^processor /proc/cpuinfo)

KERNEL_DIR=$PWD
ORIGINAL_OUTPUT_DIR="$KERNEL_DIR/arch/$ARCH/boot"
OUTPUT_DIR="$KERNEL_DIR/out"
KERNEL_ZIP="testkernel"


ERROR=0
HEAD=1
WARNING=2

function printfc() {
        if [[ $2 == $ERROR ]]; then
                printf "\e[1;31m$1\e[0m"
                return
        fi;
        if [[ $2 == $HEAD ]]; then
                printf "\e[1;32m$1\e[0m"
                return
        fi;
        if [[ $2 == $WARNING ]]; then
                printf "\e[1;35m$1\e[0m"
                return
        fi;
}

function generate_version()
{
        if [[ -f "$KERNEL_DIR/.git/HEAD" && -f "$KERNEL_DIR/anykernel/anykernel.sh" ]]; then
                local updated_kernel_name
                local anykernel_name
                local current_branch

                anykernel_name=$(awk -F"=" '/kernel.string/{print $2}' "$KERNEL_DIR/anykernel/anykernel.sh")
                current_branch=$(echo "$kernel_name" | awk -F"-" '{print $2}')

                if [[ ("$current_branch" == "stable" || "$current_branch" == "staging") ]]; then
                        updated_kernel_name=$kernel_name
                else
                        if [[ ! -f "$KERNEL_DIR/version" ]]; then
                                echo "build_number=0" > "$KERNEL_DIR/version"
                        fi;

                        awk -F"=" '{$2+=1; print $1"="$2}' "$KERNEL_DIR/version" > tmpfile
                        mv tmpfile "$KERNEL_DIR/version"

                        current_build=$(awk -F"=" '{print $2}' "$KERNEL_DIR/version")

                        export LOCALVERSION="-$current_branch-build$current_build"
                        updated_kernel_name="$kernel_name-build$current_build"
                fi;

                if [[ $CI == true ]]; then
                        updated_kernel_name="SmokeR24.1"
                fi

                # ✅ FIX: safer sed (handles / in branch names)
                safe_name=$(printf '%s\n' "$updated_kernel_name" | sed 's/[&/\]/\\&/g')
                sed -i "s|$anykernel_name|$safe_name|" "$KERNEL_DIR/anykernel/anykernel.sh"
        fi;
}

function make_zip()
{
        if [[ -d "$KERNEL_DIR/anykernel" ]]; then
                printfc "\nCreating zip archive\n\n" $HEAD
        else
                printfc "\nDirectory $KERNEL_DIR/anykernel does not exist\n\n" $ERROR
                return
        fi;

        if [[ -f "$ORIGINAL_OUTPUT_DIR/zImage" ]]; then
                if [[ ! -d "$PWD/anykernel/kernel/" ]]; then
                        mkdir -p "$PWD/anykernel/kernel/"
                fi;
                mv "$ORIGINAL_OUTPUT_DIR/zImage" "$PWD/anykernel/"
        else
                if [[ $dtb_only == 0 ]]; then
                        printfc "File $ORIGINAL_OUTPUT_DIR/zImage does not exist\n\n" $ERROR
                        return
                fi
        fi

        if [[ -f "$ORIGINAL_OUTPUT_DIR/dts/$dtb_name" ]]; then
                mv "$ORIGINAL_OUTPUT_DIR/dts/$dtb_name" "$PWD/anykernel/dtb"
        else
                if [[ $dtb_only == 0 ]]; then
                        printfc "File $ORIGINAL_OUTPUT_DIR/dts/$dtb_name does not exist\n\n" $ERROR
                        return
                fi
        fi

        cd "$KERNEL_DIR/anykernel"

        echo "Preparing files..."
        ls -lah

        if [[ $CI == true ]]; then
                zip_name=$KERNEL_ZIP
        else
                safe_kernel_name=$(echo "$kernel_name" | tr '/ ' '__')
                zip_name="$safe_kernel_name($(date +'%d.%m.%Y-%H.%M')).zip"
        fi

        echo "Creating zip: $zip_name"

        zip -r "$zip_name" ./*

        if [[ -f "$zip_name" ]]; then
        mkdir -p "$OUTPUT_DIR"

        printfc "\n$zip_name created, moving to $OUTPUT_DIR" $HEAD
        mv "$zip_name" "$OUTPUT_DIR"

        printfc "\nDone\n" $HEAD
else
        printfc "\nFailed to create archive\n" $ERROR
        return
fi
        cd "$KERNEL_DIR"
}

function compile()
{
        local start=$(date +%s)
        clear

        if [[ "$clean_build" == 1 ]]; then
                make clean
                make mrproper
        fi

        generate_version
        make $config
        make -j$cpus_count ARCH=$ARCH CROSS_COMPILE=$toolchain zImage

        printfc "\nCompiling device tree\n\n" $HEAD

        make -j$cpus_count ARCH=$ARCH CROSS_COMPILE=$toolchain $dtb_name

        local end=$(date +%s)
        local comp_time=$((end-start))
        printf "\e[1;32m\nKernel compiled in %02d:%02d\n\e[0m" $((($comp_time/60)%60)) $(($comp_time%60))

        make_zip
}

function compile_dtb()
{
        clear

        dtb_only=1
        generate_version
        make $config
        make -j$cpus_count ARCH=$ARCH CROSS_COMPILE=$toolchain $dtb_name

        make_zip
}

function main()
{
        clear
        echo "---------------------------------------------------"
        echo "Perform clean build?                              -"
        echo "---------------------------------------------------"
        echo "1 - Yes                                           -"
        echo "---------------------------------------------------"
        echo "2 - No                                            -"
        echo "---------------------------------------------------"
        echo "3 - Build DTB only                                -"
        echo "---------------------------------------------------"
        echo "4 - Exit                                          -"
        echo "---------------------------------------------------"
        echo "5 - Make Flashable ZIP                            -"
        echo "---------------------------------------------------"
        printf %s "Your choice: "
        read env

        case $env in
                1) clean_build=1;compile;;
                2) compile;;
                3) compile_dtb;;
                4) clear;return;;
                5) make_zip;;
                *) main;;
        esac
}

if [[ $CI == true ]]; then
        clean_build=1
        toolchain="arm-linux-gnueabihf-"
        compile
else
        toolchain="$HOME/globaltoolchain/bin/arm-linux-gnueabihf-"
        main
fi
