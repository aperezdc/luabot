all:
clean:

.PHONY: all clean

ALL_ITEMS := $(patsubst %.build,%,$(wildcard *.build))

define ITEM
$1: $1.build
	@sh $$< build
clean-$1: $1.build
	@sh $$< clean
.PHONY: $1 clean-$1
all: $1
clean: clean-$1
endef

$(foreach X,$(ALL_ITEMS),$(eval $(call ITEM,$X)))
