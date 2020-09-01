#!/usr/bin/env python3
''' 20200827 - TRCM - Lookup the org structure for a given user '''
# pip3 install ldap3

import sys
import codecs
import logging
from ldap3 import (Server, Connection, SUBTREE, AUTO_BIND_NO_TLS,
                   ALL, ALL_ATTRIBUTES, core)
from ldap3.utils.log import (set_library_log_detail_level,
                             set_library_log_hide_sensitive_data,
                             OFF)
# ldap3 : available loglevels to import : OFF, BASIC, NETWORK, EXTENDED

LDAP_NAME = '_redacted_'
LDAP_PORT = 389
LDAP_SSL = False
LDAP_USER = '_redacted_'
LDAP_PASS_ENCRYPTED = '_redacted_'
LDAP_BASE = '_redacted_'

logging.basicConfig(filename='/tmp/org.log', level=logging.DEBUG)
set_library_log_detail_level(OFF)
set_library_log_hide_sensitive_data(True)  # do not log password

DEBUG = False


def ldap_bind(server, port, ssl, username, encrypted_password):
    ''' Bind to the LDAP server '''
    bind = Connection(Server(server, port=port, use_ssl=ssl, get_info=ALL),
                      auto_bind=AUTO_BIND_NO_TLS, read_only=True,
                      check_names=True, fast_decoder=False,  # for better log
                      raise_exceptions=True, user=username,
                      password=codecs.decode(encrypted_password, 'rot_13'))
    return bind


def by_uid(ldap, uid):
    ''' Search LDAP for a CN / CommonName '''
    raw_filter = fr"(dbntloginid=*{uid})"
    ldap.search(search_base=LDAP_BASE,
                search_filter=raw_filter,
                search_scope=SUBTREE,
                attributes=ALL_ATTRIBUTES,
                get_operational_attributes=True)
    return ldap


def by_dbdirid(ldap, dirid):
    ''' Search LDAP for a dbdirid '''
    raw_filter = fr"(dbdirid={dirid})"
    ldap.search(search_base=LDAP_BASE,
                search_filter=raw_filter,
                search_scope=SUBTREE,
                attributes=ALL_ATTRIBUTES,
                get_operational_attributes=True)
    return ldap


def by_email(ldap, email):
    ''' Search LDAP for an email address '''
    raw_filter = fr"(mail={email})"
    ldap.search(search_base=LDAP_BASE,
                search_filter=raw_filter,
                search_scope=SUBTREE,
                attributes=ALL_ATTRIBUTES,
                get_operational_attributes=True)
    return ldap


def show_result(user):
    ''' Format and print the results we found in LDAP '''
    col = {
        'RED': '\33[31m',
        'GRN': '\33[32m',
        'YLW': '\33[33m',
        'BLU': '\33[34m',
        'VIO': '\33[35m',
        'BEI': '\33[36m',
        'WHI': '\33[37m',
        'END': '\33[0m'
        }

    def user_format(first, last, role, dirid):
        ''' Define a template for print formatting '''
        return f'{col["GRN"]}+ {first} {last} ({role}) [{dirid}]{col["END"]}'

    def attr_format1(attr, val):
        ''' Define a template for print formatting '''
        i = 2  # Attribute indent
        wid = 14  # Attribute title width padding
        return f"{' '*i}- {col['BEI']}{attr:{wid}}{col['END']} {val}"

    def attr_format2(attr, val1, val2):
        ''' Define a template for print formatting '''
        i = 2  # Attribute indent
        wid = 14  # Attribute title width padding
        return f"{' '*i}- {col['BEI']}{attr:{wid}}{col['END']} {val1}, {val2}"

    # TODO - all these ifs are lame, must be a better way...?
    print(user_format(user.givenName, user.sn, user.hrrole, user.dbdirid))
    if 'function' in user:
        print(attr_format1("Function:", user.function))
    if 'dbsecretary' in user:
        print(attr_format1("Secretary:", user.dbsecretary))
    print(attr_format2("CostCenter:", user.dbcostcenterdesc,
                       user.dbcostcenter))
    print(attr_format1("UBR:", user.hrubrcode))
    if 'dbpostalstreet' in user:
        print(attr_format2("Address:", user.dbpostalstreet,
                           user.dblocationcountry))
    print(attr_format1("Phone:", user.telephoneNumber))
    print(attr_format1("eMail:", user.mail))
    if 'dbvmruri' in user:
        print(attr_format1("VMR:", str(user.dbvmruri)+"@video.db.com"))
    if 'dbjpegphotourl' in user:
        print(attr_format1("Photo:", user.dbjpegphotourl))
    print(attr_format1("HR name:", user.hrcn))


# TODO - we need to use argparse, stop being lazy
if len(sys.argv) < 1:
    print("Provide an NT Login ID / email address / dbdirid !")
    sys.exit()

if len(sys.argv) > 2:
    if sys.argv[2] == "-d":
        DEBUG = True


# Setup a bind connection for our search queries
try:
    conn = ldap_bind(LDAP_NAME, LDAP_PORT, LDAP_SSL,
                     LDAP_USER, LDAP_PASS_ENCRYPTED)
    if DEBUG:
        print(conn.server.info)
except core.exceptions.LDAPBindError as error:
    print(f"[!] Can't bind to LDAP : {LDAP_NAME}:{LDAP_PORT} (SSL:{LDAP_SSL})")
    print(f"[!] {error}")
    sys.exit(1)


# Are we provided a loginID, an email, or a dbdirid ?
if sys.argv[1].isdigit():
    ldap_result = by_dbdirid(conn, sys.argv[1])
elif '@' in sys.argv[1]:
    ldap_result = by_email(conn, sys.argv[1])
else:
    ldap_result = by_uid(conn, sys.argv[1])


# Lets have lots of raw LDAP response if we want it
if DEBUG:
    print(ldap_result.response_to_json())


# Iterate over the responses, recursing into 'dblegalreportstodbdirid'
if ldap_result.entries:
    for person in sorted(ldap_result.entries):
        show_result(person)

        while ldap_result.entries:
            try:
                ldap_result = by_dbdirid(conn,
                                         str(person.dblegalreportstodbdirid))
            except NameError:
                break
            except core.exceptions.LDAPCursorAttributeError:
                break

            for person in sorted(ldap_result.entries):
                show_result(person)
