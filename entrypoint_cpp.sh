#!/bin/bash
# shellcheck disable=SC2155

set -e

# Following variables are declared/defined in parent script
preselected_files=${preselected_files:-""}
print_to_console=${print_to_console:-false}
use_extra_directory=${use_extra_directory:-false}
common_ancestor=${common_ancestor:-""}

FLAWFINDER_ARGS="${INPUT_FLAWFINDER_ARGS//$'\n'/}"
FLAWFINDER_TGTS="${INPUT_FLAWFINDER_TARGETS//$'\n'/}"
CPPCHECK_ARGS="${INPUT_CPPCHECK_ARGS//$'\n'/}"
INFER_ARGS="${INPUT_FBINFER_ARGS//$'\n'/}"
CLANG_TIDY_ARGS="${INPUT_CLANG_TIDY_ARGS//$'\n'/}"

WS_BASE="$GITHUB_WORKSPACE/build"
WS_INFER="$GITHUB_WORKSPACE/build/infer-out"

cd build

if [ "$INPUT_REPORT_PR_CHANGES_ONLY" = true ]; then
  if [ -z "$preselected_files" ]; then
        # Create empty files
        touch flawfinder.txt
        touch cppcheck.txt
        touch infer.json
        touch clang_tidy.txt

        cd /
        python3 -m src.static_analysis_cpp -ff "$WS_BASE/flawfinder.txt" -cc "$WS_BASE/cppcheck.txt" -fi "$WS_BASE/infer.json" -ct "$WS_BASE/clang_tidy.txt" -o "$print_to_console" -fk "$use_extra_directory" --common "$common_ancestor" --head "origin/$GITHUB_HEAD_REF"
        exit 0
   fi
fi

if [ "$INPUT_USE_CMAKE" = true ]; then
    # Trim trailing newlines
    INPUT_CMAKE_ARGS="${INPUT_CMAKE_ARGS%"${INPUT_CMAKE_ARGS##*[![:space:]]}"}"
    debug_print "Running cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON $INPUT_CMAKE_ARGS -S $GITHUB_WORKSPACE -B $(pwd)"
    eval "cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON $INPUT_CMAKE_ARGS -S $GITHUB_WORKSPACE -B $(pwd)"
fi

if [ -z "$INPUT_EXCLUDE_DIR" ]; then
    files_to_check=$(python3 /src/get_files_to_check.py -dir="$GITHUB_WORKSPACE" -preselected="$preselected_files" -lang="c++")
    debug_print "Running: files_to_check=python3 /src/get_files_to_check.py -dir=\"$GITHUB_WORKSPACE\" -preselected=\"$preselected_files\" -lang=\"c++\")"
else
    files_to_check=$(python3 /src/get_files_to_check.py -exclude="$GITHUB_WORKSPACE/$INPUT_EXCLUDE_DIR" -dir="$GITHUB_WORKSPACE" -preselected="$preselected_files" -lang="c++")
    debug_print "Running: files_to_check=python3 /src/get_files_to_check.py -exclude=\"$GITHUB_WORKSPACE/$INPUT_EXCLUDE_DIR\" -dir=\"$GITHUB_WORKSPACE\" -preselected=\"$preselected_files\" -lang=\"c++\")"
fi

debug_print "FLAWFINDER_ARGS = $FLAWFINDER_ARGS"
debug_print "FLAWFINDER_TGTS = $FLAWFINDER_TGTS"
debug_print "Files to check = $files_to_check"
debug_print "CPPCHECK_ARGS = $CPPCHECK_ARGS"
debug_print "CLANG_TIDY_ARGS = $CLANG_TIDY_ARGS"
debug_print "INFER_ARGS = $INFER_ARGS"
debug_print "WS_BASE = $WS_BASE"
debug_print "WS_INFER = $WS_INFER"

if [ -z "$files_to_check" ]; then
    echo "No files to check"

else
    for ffdir in $FLAWFINDER_TGTS; do
        dir_name=$(echo "$ffdir" | tr '/' '_')

        debug_print "Running flawfinder $FLAWFINDER_ARGS for files in /$GITHUB_WORKSPACE/$ffdir..."
        eval flawfinder "$FLAWFINDER_ARGS" "/$GITHUB_WORKSPACE/$ffdir" >>"flawfinder_$dir_name.txt" 2>&1 || true
    done

    cat flawfinder_*.txt > flawfinder.txt

    if [ "$INPUT_USE_CMAKE" = true ]; then
        for file in $files_to_check; do
            exclude_arg=""
            if [ -n "$INPUT_EXCLUDE_DIR" ]; then
                exclude_arg="-i$GITHUB_WORKSPACE/$INPUT_EXCLUDE_DIR"
            fi

            # Replace '/' with '_'
            file_name=$(echo "$file" | tr '/' '_')

            debug_print "Running cppcheck --project=compile_commands.json $CPPCHECK_ARGS --file-filter=$file --output-file=cppcheck_$file_name.txt $exclude_arg"
            eval cppcheck --project=compile_commands.json "$CPPCHECK_ARGS" --file-filter="$file" --output-file="cppcheck_$file_name.txt" "$exclude_arg" || true
        done

        cat cppcheck_*.txt > cppcheck.txt

        debug_print "Running infer run --no-progress-bar --compilation-database compile_commands.json $INFER_ARGS..."
        eval infer run --no-progress-bar --compilation-database compile_commands.json "$INFER_ARGS" || true

        # Excludes for clang-tidy are handled in python script
        debug_print "Running run-clang-tidy-19 $CLANG_TIDY_ARGS -p $(pwd) $files_to_check >>clang_tidy.txt 2>&1"
        eval run-clang-tidy-19 "$CLANG_TIDY_ARGS" -p "$(pwd)" "$files_to_check" >clang_tidy.txt 2>&1 || true

    else
        debug_print "Running cppcheck $files_to_check $CPPCHECK_ARGS --output-file=cppcheck.txt ..."
        eval cppcheck "$files_to_check" "$CPPCHECK_ARGS" --output-file=cppcheck.txt || true

        debug_print "Running infer run --no-progress-bar $INFER_ARGS..."
        eval infer run --no-progress-bar "$INFER_ARGS" || true

        debug_print "Running run-clang-tidy-19 $CLANG_TIDY_ARGS $files_to_check >>clang_tidy.txt 2>&1"
        eval run-clang-tidy-19 "$CLANG_TIDY_ARGS" "$files_to_check" >clang_tidy.txt 2>&1 || true
    fi

    cd /

    python3 -m src.static_analysis_cpp -ff "$WS_BASE/flawfinder.txt" -cc "$WS_BASE/cppcheck.txt" -fi "$WS_INFER/report.json" -ct "$WS_BASE/clang_tidy.txt" -o "$print_to_console" -fk "$use_extra_directory" --common "$common_ancestor" --head "origin/$GITHUB_HEAD_REF"
fi
