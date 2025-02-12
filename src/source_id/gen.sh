#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE[0]}")"

file="source_id.ml"

if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]
then echo "let id = \"$(git describe --always --dirty)\"" > $file.tmp
elif [ -n "$out" ]
then echo "let id = \"$(echo $out|cut -d/ -f4|cut -d- -f1|fold -w8 | paste -sd'-' -)\"" > $file.tmp
else echo "let id = \"unidentified version\"" > $file.tmp
fi
if [ ! -e $file ] || ! cmp -s $file.tmp $file
then mv $file.tmp $file
else rm -f $file.tmp
fi


