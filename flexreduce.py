''' Process a bigfile into a not-so-bigfile '''
import argparse
import os
import sys

REDUCE_STRING = "ADVANCED_COMPRESSION"
REDUCE_STRING_INDEX = 2
REDUCE_KEY1_INDEX = 0
REDUCE_KEY2_INDEX = 1

def parse_bigfile(infile, outfile):
    ''' Write lines from infile, with only one ADVANCED_COMPRESSION line
        per unique {key1,key2} pair seen.
    '''
    with open(infile, 'r') as bigfile:
        with open(outfile, 'w') as smallfile:
            lines_read = 0
            lines_written = 0
            lines_reduced = 0
            seen = {}

            status("-", "Reducing lines where " + REDUCE_STRING
                   + " appears at index " + str(REDUCE_STRING_INDEX)
                   + " ...")

            for line in bigfile:
                lines_read += 1

                if "," not in line:   # Print and move on if it doesn't look like CSV
                    lines_written += 1
                    smallfile.write(line)
                    continue

                row = line.split(",")

                if row[REDUCE_STRING_INDEX] == REDUCE_STRING:
                    key = row[REDUCE_KEY1_INDEX] + row[REDUCE_KEY2_INDEX]
                    if key in seen:
                        seen[key] += 1
                        lines_reduced += 1
                    else:
                        seen[key] = seen.setdefault(key, 0)
                        lines_written += 1
                        smallfile.write(line)
                else:
                    lines_written += 1
                    smallfile.write(line)

        status("+", "Input lines   : " + str(lines_read))
        status("-", "Reduced lines : " + str(lines_reduced))
        status("+", "Output lines  : " + str(lines_written))

def status(level, msg):
    ''' Print a status message with colour '''
    col = {
        'BLACK' : '\33[30m',
        'RED'   : '\33[31m',
        'GREEN' : '\33[32m',
        'YELLOW': '\33[33m',
        'BLUE'  : '\33[34m',
        'VIOLET': '\33[35m',
        'BEIGE' : '\33[36m',
        'WHITE' : '\33[37m',
        'END'   : '\33[0m'
        }
    if level == "+":
        print(f" {col['GREEN']}[+]{col['END']} {msg}")
    elif level == "-":
        print(f" {col['YELLOW']}[-]{col['END']} {msg}")
    elif level == "!":
        print(f" {col['RED']}[!]{col['END']} {msg}")
        sys.exit(1)
    else:
        print(f" {col['WHITE']}[{level}]{col['END']} {msg}")

def get_filename_arguments():
    ''' Get the command line arguments, and check if they're files '''
    parser = argparse.ArgumentParser()
    parser.add_argument("inputfile")
    parser.add_argument("outputfile")
    args = parser.parse_args()
    if os.path.isfile(args.inputfile):
        status("+", "Input file    : " + args.inputfile)
    else:
        status("!", "Not a file    : " + args.inputfile)
    if os.path.isfile(args.outputfile):
        status("!", "Output file already exists!")
    else:
        status("+", "Output file   : " + args.outputfile)
    return (args.inputfile, args.outputfile)

if __name__ == '__main__':
    parse_bigfile(*get_filename_arguments())
