LDLIBS += -lpthread
CPPFLAGS += -g
all:lu lucuda
lu:lucuda.cu
	cp lucuda.cu lucuda.cpp
	g++ $(CPPFLAGS) $^ -o $@ $(LDLIBS)
lucuda:lucuda.cu
	/Developer/NVIDIA/CUDA-7.5/bin/nvcc $(CPPFLAGS) $^ -o $@
clean:
	rm -f lu lucuda
