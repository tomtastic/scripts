#!/usr/bin/env python3
"""Reduce the size of Flexera BIGDATA files to avoid out-of-memory errors

This is achieved by only retaining one "ADVANCED_COMPRESSION" line for
each {database, user} pair mentioned.
"""
import argparse
import itertools
import os
import sys
import threading
import time

REDUCE_FEATURE_STRING = "ADVANCED_COMPRESSION"
REDUCE_FEATURE_STRING_INDEX = 5
DATABASE_KEY_INDEX = 4
USER_KEY_INDEX = 10


def parse_bigfile(infile, outfile):
    """Reduce lines from an input file, to an output file.

    Args:
        infile: The BIGDATA file to process (usually those over ~300MB)
        outfile: The reduced file to write out

    Returns:
        Number of lines {read, reduced, written}
    """
    try:
        # Ignore non-UTF8 chars (eg. from a windows-1252 codepage)
        with open(infile, 'r', encoding='utf-8', errors='ignore') as bigfile:
            with open(outfile, 'w', encoding='utf-8') as smallfile:
                lines_read = 0
                lines_written = 0
                lines_reduced = 0
                seen = {}

                # Lets create a work indicator
                spinner = Spinner()
                spinner.colours = {'spin':'YELLOW', 'done':'GREEN'}
                spinner.done_message = '+'
                spinner.spin_message = ("Reducing lines with " + REDUCE_FEATURE_STRING + \
                                        " at index " + str(REDUCE_FEATURE_STRING_INDEX))
                spinner.init()
                skipped = False

                try:
                    for line in bigfile:
                        lines_read += 1

                        if ";" not in line:   # Early exit if not relavent line
                            lines_written += 1
                            smallfile.write(line)
                            continue

                        row = line.split(";")

                        if len(row) < USER_KEY_INDEX + 1:
                            lines_written += 1
                            smallfile.write(line)
                            continue

                        if REDUCE_FEATURE_STRING in row[REDUCE_FEATURE_STRING_INDEX]:
                            key = row[DATABASE_KEY_INDEX] + ":" + row[USER_KEY_INDEX]
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

                except (KeyboardInterrupt, SystemExit):
                    skipped = True
                    print()
                finally:
                    spinner.stop(skipped)

    except (KeyboardInterrupt, SystemExit):
        sys.exit(1)

    return (lines_read, lines_reduced, lines_written)


def status(level, msg):
    """Print a status message with colour

    Args:
        level: String defining severity (eg. '!' = error, '+' = informational)
        msg: String to display

    Returns:
        Colour formatted message
    """

    col = {
        'RED':'\33[31m',
        'GREEN':'\33[32m',
        'YELLOW':'\33[33m',
        'BLUE':'\33[34m',
        'VIOLET':'\33[35m',
        'BEIGE':'\33[36m',
        'WHITE':'\33[37m',
        'END':'\33[0m'
        }
    if level == "+":
        print(f" {col['GREEN']}[{level}]{col['END']} {msg}")
    elif level == "-":
        print(f" {col['YELLOW']}[{level}]{col['END']} {msg}")
    elif level == "!":
        print(f" {col['RED']}[{level}]{col['END']} {msg}")
        sys.exit(1)
    else:
        print(f" {col['WHITE']}[{level}]{col['END']} {msg}")


def get_filename_arguments():
    """Get the command line arguments, and check if they're files"""
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


class Spinner(threading.Thread):
    """Represents a work indicator, handled in a separate thread"""

    # Spinner glyphs
    #glyphs = ('|/-\\|')
    #glyphs = ('-+*+-')
    #glyphs = ('.oOOo')
    glyphs = (u'▖▌▘▀▝▐▗▄')
    # Default colours
    colours = {
        'spin':'END',
        'done':'END'
        }
    # Some colours
    col = {
        'RED':'\33[31m',
        'GREEN':'\33[32m',
        'YELLOW':'\33[33m',
        'BLUE':'\33[34m',
        'VIOLET':'\33[35m',
        'BEIGE':'\33[36m',
        'WHITE':'\33[37m',
        'END':'\33[0m'
        }
    # Message to output while spin
    spin_message = ''
    # Message to output when done
    done_message = ''
    # Time between spins
    spin_delay = 0.1

    def __init__(self, *args, **kwargs):
        '''Spinner constructor'''
        threading.Thread.__init__(self, *args, **kwargs)
        self.daemon = True
        self.__started = False
        self.__stopped = False
        self.__glyphs = itertools.cycle(iter(self.glyphs))

    def __call__(self, func, *args, **kwargs):
        '''Convenient way to run a routine with a spinner'''
        self.init()
        skipped = False

        try:
            return func(*args, **kwargs)
        except (KeyboardInterrupt, SystemExit):
            skipped = True
        finally:
            self.stop(skipped)

    def init(self):
        '''Shows a spinner'''
        self.__started = True
        self.start()

    def run(self):
        '''Spins the spinner while do some task'''
        while not self.__stopped:
            self.spin()

    def spin(self):
        '''Spins the spinner'''
        if not self.__started:
            raise NotStarted('You must call init() first before using spin()')

        if sys.stdin.isatty():
            sys.stdout.write('\r')
            sys.stdout.write(f' {self.col[self.colours["spin"]]}'\
                             f'[{next(self.__glyphs)}]'\
                             f'{self.col["END"]} {self.spin_message}')
            sys.stdout.flush()
            time.sleep(self.spin_delay)

    def stop(self, skipped=None):
        '''Stops the spinner'''
        if not self.__started:
            raise NotStarted('You must call init() first before using stop()')

        self.__stopped = True
        self.__started = False

        if sys.stdin.isatty() and not skipped:
            sys.stdout.write('\r')
            sys.stdout.write(f' {self.col[self.colours["done"]]}'\
                             f'[{self.done_message}]'\
                             f'{self.col["END"]} {self.spin_message}')
            sys.stdout.write('\n')
            sys.stdout.flush()


class NotStarted(Exception):
    '''Spinner not started exception'''


if __name__ == '__main__':
    (READ, REDUCED, WRITTEN) = parse_bigfile(*get_filename_arguments())
    status("+", "Input lines   : " + str(READ))
    status("+", "Reduced lines : " + str(REDUCED))
    status("+", "Output lines  : " + str(WRITTEN)
           + " (-" + str(round((1-WRITTEN/READ)*100, 1)) + "%)")
    print()
