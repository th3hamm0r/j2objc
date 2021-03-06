# Copyright 2011 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Makefile for building and running the iOS emulation library unit tests.
#
# Author: Tom Ball

.SUFFIXES:

default: test

include environment.mk
include test_sources.mk
include $(J2OBJC_ROOT)/make/translate_macros.mk

ALL_TEST_SOURCES = $(TEST_SOURCES) $(ARC_TEST_SOURCES) $(COPIED_ARC_TEST_SOURCES)
ALL_SUITE_SOURCES = $(SUITE_SOURCES)

TESTS_TO_RUN = $(filter-out $(TESTS_TO_SKIP),$(ALL_TEST_SOURCES))
TESTS_TO_RUN := $(subst /,.,$(TESTS_TO_RUN:%.java=%))

ALL_TESTS_CLASS = AllJreTests
# Creates a test suit that includes all classes in ALL_TEST_SOURCES.
ALL_TESTS_SOURCE = $(RELATIVE_TESTS_DIR)/AllJreTests.java

SUPPORT_OBJS = $(SUPPORT_SOURCES:%.java=$(TESTS_DIR)/%.o) $(NATIVE_SOURCES:%.cpp=$(TESTS_DIR)/%.o)
TEST_OBJS = \
    $(ALL_TEST_SOURCES:%.java=$(TESTS_DIR)/%.o) \
    $(ALL_SUITE_SOURCES:%.java=$(TESTS_DIR)/%.o) \
    $(TESTS_DIR)/$(ALL_TESTS_CLASS).o

TEST_RESOURCES = $(TEST_RESOURCES_RELATIVE:%=$(RESOURCES_DEST_DIR)/%)

JUNIT_DIST_JAR = $(DIST_JAR_DIR)/$(JUNIT_JAR)

INCLUDE_DIRS = $(TESTS_DIR) $(TESTS_DIR)/arc $(CLASS_DIR) $(EMULATION_CLASS_DIR)
INCLUDE_ARGS = $(INCLUDE_DIRS:%=-I%)

TEST_JOCC := ../dist/j2objcc -g $(WARNINGS)
LINK_FLAGS := -ljre_emul -l junit -L$(TESTS_DIR) -l test-support
COMPILE_FLAGS := $(INCLUDE_ARGS) -c -Wno-objc-redundant-literal-use -Wno-format -Werror \
  -Wno-parentheses

ifeq ($(OBJCPP_BUILD), YES)
LINK_FLAGS += -lc++ -ObjC++
else
LINK_FLAGS += -ObjC
endif

SUPPORT_LIB = $(TESTS_DIR)/libtest-support.a
TEST_BIN = $(TESTS_DIR)/jre_unit_tests

TRANSLATE_ARGS = -classpath $(JUNIT_DIST_JAR) -Werror -sourcepath $(TEST_SRC):$(GEN_JAVA_DIR) \
    -encoding UTF-8 --prefixes Tests/resources/prefixes.properties
TRANSLATE_SOURCES = $(SUPPORT_SOURCES) $(TEST_SOURCES) $(SUITE_SOURCES) $(ALL_TESTS_CLASS).java
TRANSLATE_SOURCES_ARC = $(ARC_TEST_SOURCES) $(COPIED_ARC_TEST_SOURCES)
TRANSLATED_OBJC = $(TRANSLATE_SOURCES:%.java=$(TESTS_DIR)/%.m)
TRANSLATED_OBJC_ARC = $(TRANSLATE_SOURCES_ARC:%.java=$(TESTS_DIR)/arc/%.m)

TRANSLATE_ARTIFACT := $(call emit_translate_rule,\
  jre_emul_tests,\
  $(TESTS_DIR),\
  $(SUPPORT_SOURCES) $(TEST_SOURCES) $(SUITE_SOURCES) $(ALL_TESTS_SOURCE),\
  ,\
  $(TRANSLATE_ARGS))

TRANSLATE_ARTIFACT_ARC := $(call emit_translate_rule,\
  jre_emul_tests_arc,\
  $(TESTS_DIR)/arc,\
  $(ARC_TEST_SOURCES) $(COPIED_ARC_TEST_SOURCES:%=$(GEN_JAVA_DIR)/%),\
  ,\
  $(TRANSLATE_ARGS) -use-arc)

TRANSLATE_ARTIFACTS = $(TRANSLATE_ARTIFACT) $(TRANSLATE_ARTIFACT_ARC)

# Make sure any generated source files are generated prior to translation.
translate_dependencies: $(COPIED_ARC_TEST_SOURCES:%=$(GEN_JAVA_DIR)/%)

$(TRANSLATED_OBJC): $(TRANSLATE_ARTIFACT)
	@:

$(TRANSLATED_OBJC_ARC): $(TRANSLATE_ARTIFACT_ARC)
	@:

ifdef GENERATE_TEST_COVERAGE
TEST_JOCC += -ftest-coverage -fprofile-arcs
endif

all-tests: test run-xctests

test: run-tests

support-lib: $(SUPPORT_LIB)

build: support-lib $(TEST_OBJS)
	@:

translate-all: translate
	@:

link: build $(TEST_BIN)

resources: $(TEST_RESOURCES)
	@:

define resource_copy_rule
$(RESOURCES_DEST_DIR)/%: $(1)/%
	@mkdir -p `dirname $$@`
	@cp $$< $$@
endef

$(foreach root,$(TEST_RESOURCE_ROOTS),$(eval $(call resource_copy_rule,$(root))))

# A bug in make 3.81 causes subprocesses to inherit a generous amount of stack.
# This distorts the fact that the default stack size is 8 MB for a 64-bit OS X
# binary. Work around with ulimit override.
#
# See http://stackoverflow.com/questions/16279867/gmake-change-the-stack-size-limit
# and https://savannah.gnu.org/bugs/?22010
run-tests: link resources $(TEST_BIN) run-initialization-test run-core-size-test
	@ulimit -s 8192 && $(TEST_BIN) org.junit.runner.JUnitCore $(ALL_TESTS_CLASS)

run-initialization-test: $(TESTS_DIR)/jreinitialization
	@$(TESTS_DIR)/jreinitialization > /dev/null 2>&1

run-core-size-test: $(TESTS_DIR)/core_size \
  $(TESTS_DIR)/full_jre_size \
  $(TESTS_DIR)/core_plus_android_util \
  $(TESTS_DIR)/core_plus_beans \
  $(TESTS_DIR)/core_plus_channels \
  $(TESTS_DIR)/core_plus_concurrent \
  $(TESTS_DIR)/core_plus_io \
  $(TESTS_DIR)/core_plus_net \
  $(TESTS_DIR)/core_plus_security \
  $(TESTS_DIR)/core_plus_sql \
  $(TESTS_DIR)/core_plus_ssl \
  $(TESTS_DIR)/core_plus_util \
  $(TESTS_DIR)/core_plus_xml \
  $(TESTS_DIR)/core_plus_zip
	@for bin in $^; do \
	  echo Binary size for $$(basename $$bin):; \
	  ls -l $$bin; \
	  echo Number of classes: `nm $$bin | grep -c "S _OBJC_CLASS_"`; \
	done

run-beans-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore org.apache.harmony.beans.tests.java.beans.AllTests

run-concurrency-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore ConcurrencyTests

run-io-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore libcore.java.io.SmallTests

run-json-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore org.json.SmallTests

run-java8-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore com.google.j2objc.java8.SmallTests

run-logging-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore \
	    org.apache.harmony.logging.tests.java.util.logging.AllTests

run-net-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore libcore.java.net.SmallTests

run-text-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore libcore.java.text.SmallTests libcore.java.text.LargeTests

run-zip-tests: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore libcore.java.util.zip.SmallTests

run-zip-tests-large: link resources $(TEST_BIN)
	@$(TEST_BIN) org.junit.runner.JUnitCore libcore.java.util.zip.LargeTests

# Run this when the above has errors and JUnit doesn't report which
# test failed or hung.
run-each-test: link resources $(TEST_BIN)
	@for test in $(subst /,.,$(ALL_TEST_SOURCES:%.java=%)); do \
	  echo $$test:; \
	  $(TEST_BIN) org.junit.runner.JUnitCore $$test; \
	done

# Build and run the JreEmulation project's test bundle, then close simulator app.
# Note: the simulator app's name was changed to "Simulator" in Xcode 7.
run-xctests: test
	@xcodebuild -project JreEmulation.xcodeproj -scheme jre_emul -destination \
	    'platform=iOS Simulator,name=iPhone 7 Plus' test
	@killall 'Simulator'

$(SUPPORT_LIB): $(SUPPORT_OBJS)
	@echo libtool -o $(SUPPORT_LIB)
	@libtool -static -o $(SUPPORT_LIB) $(SUPPORT_OBJS)

clean:
	@rm -rf $(TESTS_DIR)

$(TESTS_DIR):
	@mkdir -p $@

$(TESTS_DIR)/%.o: $(TESTS_DIR)/%.m | $(TRANSLATE_ARTIFACTS)
	@mkdir -p $(@D)
	@echo j2objcc -c $?
	@$(TEST_JOCC) $(COMPILE_FLAGS) -o $@ $<

$(TESTS_DIR)/%.o: $(TESTS_DIR)/arc/%.m | $(TRANSLATE_ARTIFACTS)
	@mkdir -p $(@D)
	@echo j2objcc -c $?
	@$(TEST_JOCC) $(COMPILE_FLAGS) -fobjc-arc -o $@ $<

$(TESTS_DIR)/%.o: $(ANDROID_NATIVE_TEST_DIR)/%.cpp | $(TESTS_DIR)
	cc -g -I$(EMULATION_CLASS_DIR) -x objective-c++ -c $? -o $@ \
	  -Werror -Wno-parentheses $(GCOV_FLAGS)

$(TEST_BIN): $(TEST_OBJS) $(SUPPORT_LIB) \
        ../dist/lib/macosx/libjre_emul.a ../dist/lib/macosx/libjunit.a
	@echo Building test executable...
	@$(TEST_JOCC) $(LINK_FLAGS) -o $@ $(TEST_OBJS)

$(ALL_TESTS_SOURCE): tests.mk
	@mkdir -p $(@D)
	@xcrun awk -f gen_all_tests.sh $(TESTS_TO_RUN) > $@

$(TESTS_DIR)/jreinitialization: Tests/JreInitialization.m
	@../dist/j2objcc -o $@ -ljre_emul -ObjC -Os $?

$(GEN_JAVA_DIR)/com/google/j2objc/arc/%.java: $(MISC_TEST_ROOT)/com/google/j2objc/%.java
	@mkdir -p $(@D)
	@echo $<
	@sed 's/^package com\.google\.j2objc;$$/package com.google.j2objc.arc;/' $< > $@

$(TESTS_DIR)/core_size:
	@mkdir -p $(@D)
	../dist/j2objcc -o $@ -ObjC

$(TESTS_DIR)/full_jre_size:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_emul -o $@ -ObjC

$(TESTS_DIR)/core_plus_io:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_io -o $@ -ObjC

$(TESTS_DIR)/core_plus_net:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_net -o $@ -ObjC

$(TESTS_DIR)/core_plus_util:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_util -o $@ -ObjC

$(TESTS_DIR)/core_plus_concurrent:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_concurrent -ljre_util -o $@ -ObjC

$(TESTS_DIR)/core_plus_channels:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_channels -ljre_net -ljre_security -ljre_util -o $@ -ObjC

$(TESTS_DIR)/core_plus_security:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_security -ljre_net -o $@ -ObjC

$(TESTS_DIR)/core_plus_ssl:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_ssl -ljre_security -ljre_net -ljre_util -o $@ -ObjC

$(TESTS_DIR)/core_plus_xml:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_xml -ljre_net -ljre_security -o $@ -ObjC

$(TESTS_DIR)/core_plus_zip:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_zip -ljre_security -ljre_net -ljre_io -o $@ -ObjC

$(TESTS_DIR)/core_plus_sql:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_sql -o $@ -ObjC

$(TESTS_DIR)/core_plus_beans:
	@mkdir -p $(@D)
	../dist/j2objcc -ljre_beans -ljre_util -o $@ -ObjC

$(TESTS_DIR)/core_plus_android_util:
	@mkdir -p $(@D)
	../dist/j2objcc -landroid_util -ljre_net -ljre_util -ljre_concurrent -ljre_security -o $@ -ObjC
