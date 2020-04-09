#!/usr/bin/env bash

# A simple test runner. Synopsis:
#
# ./run.sh foo.mo [bar.mo ..]
#
# Options:
#
#    -a: Update the files in ok/
#    -d: Run on in drun (or, if not possible, in ic-ref-run)
#    -t: Only typecheck
#    -s: Be silent in sunny-day execution
#    -i: Only check mo to idl generation
#    -p: Produce perf statistics
#        only compiles and runs drun, writes stats to $PERF_OUT
#

function realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}


ACCEPT=no
DTESTS=no
IDL=no
PERF=no
MOC=${MOC:-$(realpath $(dirname $0)/../src/moc)}
MO_LD=${MO_LD:-$(realpath $(dirname $0)/../src/mo-ld)}
DIDC=${DIDC:-$(realpath $(dirname $0)/../src/didc)}
export MO_LD
WASMTIME=${WASMTIME:-wasmtime}
WASMTIME_OPTIONS="--disable-cache --cranelift"
DRUN=${DRUN:-drun}
DRUN_WRAPPER=$(realpath $(dirname $0)/drun-wrapper.sh)
IC_REF_RUN_WRAPPER=$(realpath $(dirname $0)/ic-ref-run-wrapper.sh)
IC_REF_RUN=${IC_REF_RUN:-ic-ref-run}
SKIP_RUNNING=${SKIP_RUNNING:-no}
ONLY_TYPECHECK=no
ECHO=echo

while getopts "adpstir" o; do
    case "${o}" in
        a)
            ACCEPT=yes
            ;;
        d)
            DTESTS=yes
            ;;
        p)
            PERF=yes
            ;;
        s)
            ECHO=true
            ;;
        t)
            ONLY_TYPECHECK=true
            ;;
        i)
            IDL=yes
            ;;
    esac
done

shift $((OPTIND-1))

failures=no

function normalize () {
  if [ -e "$1" ]
  then
    grep -a -E -v '^Raised by|^Raised at|^Re-raised at|^Re-Raised at|^Called from|^ *at ' $1 |
    sed 's/\x00//g' |
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' |
    sed 's/^.*[IW], hypervisor:/hypervisor:/g' |
    sed 's/wasm:0x[a-f0-9]*:/wasm:0x___:/g' |
    sed 's/prelude:[^:]*:/prelude:___:/g' |
    sed 's/prim:[^:]*:/prim:___:/g' |
    sed 's/ calling func\$[0-9]*/ calling func$NNN/g' |
    sed 's/rip_addr: [0-9]*/rip_addr: XXX/g' |
    sed 's,/private/tmp/,/tmp/,g' |
    sed 's,/tmp/.*dfinity.[^/]*,/tmp/dfinity.XXX,g' |
    sed 's,/build/.*dfinity.[^/]*,/tmp/dfinity.XXX,g' |
    sed 's,/tmp/.*ic.[^/]*,/tmp/ic.XXX,g' |
    sed 's,/build/.*ic.[^/]*,/tmp/ic.XXX,g' |
    sed 's/^.*run-dfinity\/\.\.\/drun.sh: line/drun.sh: line/g' |
    sed 's,^.*/idl/_out/,..../idl/_out/,g' | # node puts full paths in error messages
    sed 's,\([a-zA-Z0-9.-]*\).mo.mangled,\1.mo,g' |
    sed 's/trap at 0x[a-f0-9]*/trap at 0x___:/g' |
    sed 's/source location: @[a-f0-9]*/source location: @___:/g' |
    sed 's/Ignore Diff:.*/Ignore Diff: (ignored)/ig' |
    cat > $1.norm
    mv $1.norm $1
  fi
}

function run () {
  # first argument: extension of the output file
  # remaining argument: command line
  # uses from scope: $out, $file, $base, $diff_files

  local ext="$1"
  shift

  if grep -q "^//SKIP $ext$" $file; then return 1; fi

  if test -e $out/$base.$ext
  then
    echo "Output $ext already exists."
    exit 1
  fi

  $ECHO -n " [$ext]"
  "$@" >& $out/$base.$ext
  local ret=$?

  if [ $ret != 0 ]
  then echo "Return code $ret" >> $out/$base.$ext.ret
  else rm -f $out/$base.$ext.ret
  fi
  diff_files="$diff_files $base.$ext.ret"

  normalize $out/$base.$ext
  diff_files="$diff_files $base.$ext"

  return $ret
}

function run_if () {
  # first argument: a file extension
  # remaining argument: passed to run

  local ext="$1"
  shift

  if test -e $out/$base.$ext
  then
    run "$@"
  else
    return 1
  fi
}

if [ "$PERF" = "yes" ]
then
  if [ -z "$PERF_OUT" ]
  then
    echo "Warning: \$PERF_OUT not set" >&2
  fi
fi

HAVE_DRUN=no
HAVE_IC_REF_RUN=no

if [ $DTESTS = yes -o $PERF = yes ]
then
  if $DRUN --version >& /dev/null
  then
    HAVE_DRUN=yes
  else
    if [ $ACCEPT = yes ]
    then
      echo "ERROR: Could not run $DRUN, cannot update expected test output"
      exit 1
    else
      echo "WARNING: Could not run $DRUN, will skip some tests"
      HAVE_DRUN=no
    fi
  fi
fi

if [ $DTESTS = yes ]
then
  if $IC_REF_RUN --help >& /dev/null
  then
    HAVE_IC_REF_RUN=yes
  else
    if [ $ACCEPT = yes ]
    then
      echo "ERROR: Could not run $IC_REF_RUN, cannot update expected test output"
      exit 1
    else
      echo "WARNING: Could not run $IC_REF_RUN, will skip some tests"
      HAVE_IC_REF_RUN=no
    fi
  fi
fi


for file in "$@";
do
  if ! [ -r $file ]
  then
    echo "File $file does not exist."
    failures=yes
    continue
  fi

  if [ ${file: -3} == ".mo" ]
  then base=$(basename $file .mo)
  elif [ ${file: -3} == ".sh" ]
  then base=$(basename $file .sh)
  elif [ ${file: -4} == ".wat" ]
  then base=$(basename $file .wat)
  elif [ ${file: -4} == ".did" ]
  then base=$(basename $file .did)
  else
    echo "Unknown file extension in $file, expected .mo, .sh, .wat or .did"; exit 1
    failures=yes
    continue
  fi

  # We run all commands in the directory of the .mo file,
  # so that no paths leak into the output
  pushd $(dirname $file) >/dev/null

  out=_out
  ok=ok

  $ECHO -n "$base:"
  [ -d $out ] || mkdir $out
  [ -d $ok ] || mkdir $ok

  rm -f $out/$base.*

  # First run all the steps, and remember what to diff
  diff_files=

  if [ ${file: -3} == ".mo" ]
  then
    # extra flags (allow shell variables there)
    moc_extra_flags="$(eval echo $(grep '//MOC-FLAG' $base.mo | cut -c11- | paste -sd' '))"

    # Typecheck
    run tc $MOC $moc_extra_flags --check $base.mo
    tc_succeeded=$?

    if [ "$tc_succeeded" -eq 0 -a "$ONLY_TYPECHECK" = "no" ]
    then
      if [ $IDL = 'yes' ]
      then
        run idl $MOC $moc_extra_flags --idl $base.mo -o $out/$base.did
        idl_succeeded=$?

        normalize $out/$base.did
        diff_files="$diff_files $base.did"

        if [ "$idl_succeeded" -eq 0 ]
        then
          run didc $DIDC --check $out/$base.did
        fi
      else
        if [ "$SKIP_RUNNING" != yes -a "$PERF" != yes ]
        then
          # Interpret
          run run $MOC $moc_extra_flags --hide-warnings -r $base.mo

          # Interpret IR without lowering
          run run-ir $MOC $moc_extra_flags --hide-warnings -r -iR -no-async -no-await $base.mo

          # Diff interpretations without/with lowering
          if [ -e $out/$base.run -a -e $out/$base.run-ir ]
          then
            diff -u -N --label "$base.run" $out/$base.run --label "$base.run-ir" $out/$base.run-ir > $out/$base.diff-ir
            diff_files="$diff_files $base.diff-ir"
          fi

          # Interpret IR with lowering
          run run-low $MOC $moc_extra_flags --hide-warnings -r -iR $base.mo

          # Diff interpretations without/with lowering
          if [ -e $out/$base.run -a -e $out/$base.run-low ]
          then
            diff -u -N --label "$base.run" $out/$base.run --label "$base.run-low" $out/$base.run-low > $out/$base.diff-low
            diff_files="$diff_files $base.diff-low"
          fi

        fi

        # Mangle for compilation:
        # The compilation targets do not support self-calls during canister
        # installation, so this replaces
        #
        #     actor a { … }
        #     a.go(); //CALL …
        #
        # with
        #
        #     actor a { … }
        #     //CALL …
        #
        # which actually works on the IC platform

	# needs to be in the same directory to preserve relative paths :-(
        mangled=$base.mo.mangled
        sed 's,^.*//OR-CALL,//CALL,g' $base.mo > $mangled


        # Compile
        if [ $DTESTS = yes ]
        then
          run comp $MOC $moc_extra_flags --hide-warnings --map -c $mangled -o $out/$base.wasm
          run comp-ref $MOC $moc_extra_flags -ref-system-api --hide-warnings --map -c $mangled -o $out/$base.ref.wasm
	elif [ $PERF = yes ]
	then
          run comp $MOC $moc_extra_flags --hide-warnings --map -c $mangled -o $out/$base.wasm
	else
          run comp $MOC $moc_extra_flags -wasi-system-api --hide-warnings --map -c $mangled -o $out/$base.wasm
        fi

        run_if wasm valid wasm-validate $out/$base.wasm
        run_if ref.wasm valid-ref wasm-validate $out/$base.ref.wasm

        if [ -e $out/$base.wasm ]
        then
          # Check filecheck
          if [ "$SKIP_RUNNING" != yes ]
          then
            if grep -F -q CHECK $mangled
            then
              $ECHO -n " [FileCheck]"
              wasm2wat --no-check --enable-multi-value $out/$base.wasm > $out/$base.wat
              cat $out/$base.wat | FileCheck $mangled > $out/$base.filecheck 2>&1
              diff_files="$diff_files $base.filecheck"
            fi
          fi
        fi

        # Run compiled program
        if [ "$SKIP_RUNNING" != yes ]
        then
          if [ $DTESTS = yes ]
          then
            if [ $HAVE_DRUN = yes ]; then
              run_if wasm drun-run $DRUN_WRAPPER $out/$base.wasm $mangled
            fi
            if [ $HAVE_IC_REF_RUN = yes ]; then
              run_if ref.wasm ic-ref-run $IC_REF_RUN_WRAPPER $out/$base.ref.wasm $mangled
            fi
          elif [ $PERF = yes ]
          then
            if [ $HAVE_DRUN = yes ]; then
              run_if wasm drun-run $DRUN_WRAPPER $out/$base.wasm $mangled 222> $out/$base.metrics
              if [ -e $out/$base.metrics -a -n "$PERF_OUT" ]
              then
                LANG=C perl -ne "print \"gas/$base;\$1\n\" if /^scheduler_gas_consumed_per_round_sum (\\d+)\$/" $out/$base.metrics >> $PERF_OUT;
              fi
            fi
          else
            run_if wasm wasm-run $WASMTIME $WASMTIME_OPTIONS $out/$base.wasm
          fi
        fi

        # collect size stats
        if [ "$PERF" = yes -a -e "$out/$base.wasm" ]
        then
	   if [ -n "$PERF_OUT" ]
           then
             wasm-strip $out/$base.wasm
             echo "size/$base;$(stat --format=%s $out/$base.wasm)" >> $PERF_OUT
           fi
        fi

	rm -f $mangled
      fi
    fi
  elif [ ${file: -3} == ".sh" ]
  then
    # The file is a shell script, just run it
    $ECHO -n " [out]"
    ./$(basename $file) > $out/$base.stdout 2> $out/$base.stderr
    normalize $out/$base.stdout
    normalize $out/$base.stderr
    diff_files="$diff_files $base.stdout $base.stderr"
  elif [ ${file: -4} == ".wat" ]
  then
    # The file is a .wat file, so we are expected to test linking
    $ECHO -n " [mo-ld]"
    rm -f $out/$base.{base,lib,linked}.{wasm,wat,o}
    make --quiet $out/$base.{base,lib}.wasm
    $MO_LD -b $out/$base.base.wasm -l $out/$base.lib.wasm -o $out/$base.linked.wasm > $out/$base.mo-ld 2>&1
    diff_files="$diff_files $base.mo-ld"

    if [ -e $out/$base.linked.wasm ]
    then
        run wasm2wat wasm2wat $out/$base.linked.wasm -o $out/$base.linked.wat
        diff_files="$diff_files $base.linked.wat"
    fi

  else
    # The file is a .did file, so we are expected to test the idl
    # Typecheck
    $ECHO -n " [tc]"
    $DIDC --check $base.did > $out/$base.tc 2>&1
    tc_succeeded=$?
    normalize $out/$base.tc
    diff_files="$diff_files $base.tc"

    if [ "$tc_succeeded" -eq 0 ];
    then
      $ECHO -n " [pp]"
      $DIDC --pp $base.did > $out/$base.pp.did
      sed -i 's/import "/import "..\//g' $out/$base.pp.did
      $DIDC --check $out/$base.pp.did > $out/$base.pp.tc 2>&1
      diff_files="$diff_files $base.pp.tc"

      run didc-js $DIDC --js $base.did -o $out/$base.js
      normalize $out/$base.js
      diff_files="$diff_files $base.js"

      if [ -e $out/$base.js ]
      then
        export NODE_PATH=$NODE_PATH:$ESM
        run node node -r esm $out/$base.js
      fi
    fi
  fi
  $ECHO ""

  if [ $ACCEPT = yes ]
  then
    rm -f $ok/$base.*

    for outfile in $diff_files
    do
      if [ -s $out/$outfile ]
      then
        cp $out/$outfile $ok/$outfile.ok
      else
        rm -f $ok/$outfile.ok
      fi
    done
  else
    for file in $diff_files
    do
      if [ -e $ok/$file.ok -o -e $out/$file ]
      then
        diff -a -u -N --label "$file (expected)" $ok/$file.ok --label "$file (actual)" $out/$file
        if [ $? != 0 ]; then failures=yes; fi
      fi
    done
  fi
  popd >/dev/null
done

if [ $failures = yes ]
then
  echo "Some tests failed."
  exit 1
else
  $ECHO "All tests passed."
fi
