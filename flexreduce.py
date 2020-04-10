''' Process a bigfile into a not-so-bigfile '''
import argparse
import os
import sys
import time
import threading

REDUCE_FEATURE_STRING = "ADVANCED_COMPRESSION"
REDUCE_FEATURE_STRING_INDEX = 2
DATABASE_KEY_INDEX = 0
USER_KEY_INDEX = 1

def parse_bigfile(infile, outfile):
    ''' Write lines from infile, with only one ADVANCED_COMPRESSION line
        per unique {database,user} pair seen.
    '''
    try:
        with open(infile, 'r') as bigfile:
            with open(outfile, 'w') as smallfile:
                lines_read = 0
                lines_written = 0
                lines_reduced = 0
                seen = {}

                status("-", "Reducing lines where " + REDUCE_FEATURE_STRING
                    + " appears at index " + str(REDUCE_FEATURE_STRING_INDEX)
                    + " ... ")

                with Spinner():
                    for line in bigfile:
                        lines_read += 1

                        if "," not in line:   # Print and move on if it doesn't look like CSV
                            lines_written += 1
                            smallfile.write(line)
                            continue

                        row = line.split(",")

                        if row[REDUCE_FEATURE_STRING_INDEX] == REDUCE_FEATURE_STRING:
                            key = row[DATABASE_KEY_INDEX] + row[USER_KEY_INDEX]
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
                print()

            status("+", "Input lines   : " + str(lines_read))
            status("+", "Reduced lines : " + str(lines_reduced))
            status("+", "Output lines  : " + str(lines_written))
    except (KeyboardInterrupt, SystemExit):
        sys.exit(1)

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
        print(f" {col['YELLOW']}[-]{col['END']} {msg}", end='')
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

class Spinner:
    busy = False
    delay = 0.1

    @staticmethod
    def spinning_cursor():
        while 1:
            for cursor in '|/-\\': yield cursor

    def __init__(self, delay=None):
        self.spinner_generator = self.spinning_cursor()
        if delay and float(delay): self.delay = delay

    def spinner_task(self):
        while self.busy:
            sys.stdout.write(next(self.spinner_generator))
            sys.stdout.flush()
            time.sleep(self.delay)
            sys.stdout.write('\b')
            sys.stdout.flush()

    def __enter__(self):
        self.busy = True
        threading.Thread(target=self.spinner_task).start()

    def __exit__(self, exception, value, tb):
        self.busy = False
        time.sleep(self.delay)
        if exception is not None:
            return False

if __name__ == '__main__':
    parse_bigfile(*get_filename_arguments())
