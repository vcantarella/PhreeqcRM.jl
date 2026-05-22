# Build C drivers for the reference suite.
# Each driver lives at  reference_suite/<case>/driver.c
# and is compiled to    c_build/<case>_driver

UNAME_S := $(shell uname -s)
# Use absolute paths so the rpath baked into the binary works regardless of
# where the binary is invoked from.
ROOT := $(realpath ../..)
LIB_DIR := $(ROOT)/deps/usr/lib
INC_DIR := $(ROOT)/deps/usr/include
SUITE_DIR := ../reference_suite

CC ?= cc
CFLAGS := -I$(INC_DIR) -O2 -std=c11 -Wall -Wextra

ifeq ($(UNAME_S),Darwin)
    LDFLAGS := -L$(LIB_DIR) -lPhreeqcRM -Wl,-rpath,$(LIB_DIR) \
               -Wl,-rpath,$(shell brew --prefix libomp 2>/dev/null)/lib
else
    LDFLAGS := -L$(LIB_DIR) -lPhreeqcRM -Wl,-rpath,$(LIB_DIR)
endif

CASES := $(notdir $(wildcard $(SUITE_DIR)/ex*))
SRCS  := $(foreach c,$(CASES),$(SUITE_DIR)/$(c)/driver.c)
DRIVERS := $(foreach src,$(SRCS),$(notdir $(patsubst %/driver.c,%_driver,$(src))))
EXISTING := $(foreach src,$(SRCS),$(if $(wildcard $(src)),$(notdir $(patsubst %/driver.c,%_driver,$(src)))))

all: $(EXISTING) generic_driver

%_driver: $(SUITE_DIR)/%/driver.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

generic_driver: $(SUITE_DIR)/_scripts/generic_driver.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f *_driver

.PHONY: all clean
