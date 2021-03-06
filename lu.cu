#include <iostream>
#include <stdexcept>
#include <cmath>
#include <cstdlib>
#include <sys/timeb.h>
#define diffftime(a,b) ((a.time-b.time)+(a.millitm-b.millitm)/1000.0)

//Fix some platforms missing barrier implementation
#if defined(__APPLE__) || defined(__CYGWIN32__) || defined(__CYGWIN64__)
#include "pthread_barrier.h"
#endif

//define BARRIER() and CUDA_CALLABLE differently
#ifdef __CUDACC__ 
#define CUDA_CALLABLE __host__ __device__
#define BARRIER() __syncthreads()
#else
#define CUDA_CALLABLE
#include <pthread.h>
#define BARRIER() pthread_barrier_wait(&barrier)
#endif 

#ifdef GRAPHITE
#include "carbon_user.h"
#endif

//Fix VC missing rand48 functions
#if defined(_MSC_VER)
#define lrand48() rand()
#define srand48(x) srand(x)
#endif 

using namespace std;
int N,P,B,NB;
struct timeb main_t1, main_t2, threads_t1, threads_t2;
class Block{
public:
	float*p;
	int b;
	Block(){p=NULL;}
	Block(int _b){p=NULL;b=_b;}
	CUDA_CALLABLE float& at(int x,int y){
		return p[x*b+y];
	}
};
class Matrix{
public:
	Block*p;
	int b;
	int nb;
	Matrix(){p=NULL;}
	Matrix(int _n,int _b){p=NULL;nb=_n/_b;b=_b;}
	CUDA_CALLABLE Block& getBlock(int x,int y){
		return p[x*nb+y];
	}
	CUDA_CALLABLE float& at(int x,int y){
		return getBlock(x/b,y/b).at(x%b,y%b);
	}
	void print(){
		for(int i=0;i<N;++i){
			for(int j=0;j<N;++j){
				cout<<at(i,j)<<" ";
			}
			cout<<endl;
		}
	}
}*A;
#ifndef __CUDACC__
pthread_barrier_t barrier;
#endif
void usage(char*n){
	cout<<"Usage: ./"<<n<<" N P B matrix_file\n\tN:NxN matrix\n\tP:P threads\n\tB:BxB block"<<endl;
}

// block b, referce block r, line "i" in b, line "k" in r, start column j, alpha
CUDA_CALLABLE void daxpy(Block&b , Block&r, int i, int k, int j, float alpha)
{
	for (int p = j; p<b.b; p++)     b.at(i,p) += alpha*r.at(k,p);
}
CUDA_CALLABLE void top_left(Block&b)
{
	float alpha;
	for (int k=0; k<b.b; k++) {
		/* modify subsequent columns */
		for (int i=k+1; i<b.b; i++) {
			b.at(i,k)/= b.at(k,k);
			alpha = -b.at(i,k);
			//length = n-k-1;
			daxpy(b, b, i, k, k+1, alpha);
		}
	}
}


CUDA_CALLABLE void top_right(Block&b, Block&r)
{
	float alpha;
	for (int k=0; k<b.b; k++) {
		for (int i=k+1; i<b.b; i++) {
			alpha = -r.at(i,k);
			daxpy(b, b, i, k, 0, alpha);
		}
	}
}


CUDA_CALLABLE void bottom_left(Block &b, Block&r)
{
	float alpha;
	for (int k=0; k<b.b; k++)
		for (int i=0; i<b.b; i++) {
			b.at(i,k) /= r.at(k,k);
			alpha = -b.at(i,k);
			daxpy(b, r, i, k, k+1, alpha);
		}
}


CUDA_CALLABLE void bottom_right(Block &b, Block&r1, Block&r2)
{
	float alpha;
	for (int k=0; k<b.b; k++) {
		for (int i=0; i<b.b; i++) {
			alpha = -r1.at(i,k);
			daxpy(b,r2,i,k,0,alpha);
		}
	}
}

#ifdef __CUDACC__
__global__ void thread_main(Matrix*A,int P)
#else
void* thread_main(void*p)
#endif
{

#ifdef __CUDACC__
	int thread_id=threadIdx.x;
#else
	int thread_id=*(int*)p;
	
#endif
	for(int round=0;round<A->nb;++round){
		//step 1, calculate top left
		if(thread_id==0){
			//A->getBlock(round,round);
			top_left(A->getBlock(round,round));
		}
		BARRIER();
		//step 2, bottom left and top right
		//x 0 2
		//1 x x
		//3 x x
		//0,1,2,3->()
		for(int i=thread_id;i<(A->nb-round-1)*2;i+=P){
			if(i&1){
				//bottom left
				//A->getBlock(round+(i>>1)+1,round);
				bottom_left(A->getBlock(round+(i>>1)+1,round),A->getBlock(round,round));
			}else{
				//top right
				//A->getBlock(round,round+(i>>1)+1);
				top_right(A->getBlock(round,round+(i>>1)+1),A->getBlock(round,round));
			}
		}
		BARRIER();
		//step 3, bottom right
		//x x x
		//x 0 1
		//x 2 3
		for(int i=thread_id;i<(A->nb-round-1)*(A->nb-round-1);i+=P){
			//A->getBlock(i/(NB-round-1)+round+1,i%(NB-round-1)+round+1)
			bottom_right(A->getBlock(i/(A->nb-round-1)+round+1,i%(A->nb-round-1)+round+1),
				A->getBlock(i/(A->nb-round-1)+round+1,round),
				A->getBlock(round,i%(A->nb-round-1)+round+1));
		}
		BARRIER();
	}
#ifndef __CUDACC__
	return NULL;
#endif
}

#ifdef __CUDACC__
void cuda_upload(Matrix*rm, Matrix*lm)
{
	Block*blocks=new Block[NB*NB];
#ifdef CONTIGUOUS
	for(int i=0;i<NB;++i){
		for(int j=0;j<NB;++j){
			float*p;
			if(cudaMalloc((void **)&p, sizeof(float)*B*B)!=cudaSuccess)
				throw runtime_error("cudaMalloc");
			blocks[i*NB+j].b=B;
			blocks[i*NB+j].p=p;
			cudaMemcpy(p, lm->getBlock(i,j).p, sizeof(float)*B*B, cudaMemcpyHostToDevice);
		}
	}
#else
	float*p;
	if(cudaMalloc((void **)&p, sizeof(float)*B*B*NB*NB)!=cudaSuccess)
		throw runtime_error("cudaMalloc");
	cudaMemcpy(p, lm->getBlock(0,0).p, sizeof(float)*B*B*NB*NB, cudaMemcpyHostToDevice);
	for(int i=0;i<NB;++i){
		for(int j=0;j<NB;++j){
			blocks[i*NB+j].b=B;
			blocks[i*NB+j].p=p+B*B*(i*NB+j);
		}
	}
#endif
	Block*d_blocks;
	if(cudaMalloc((void **)&d_blocks, sizeof(Block)*NB*NB)!=cudaSuccess)
		throw runtime_error("cudaMalloc");
	cudaMemcpy(d_blocks, blocks, sizeof(Block)*NB*NB, cudaMemcpyHostToDevice);
	
	Matrix*m=new Matrix(N,B);
	m->p=d_blocks;
	cudaMemcpy(rm, m, sizeof(Matrix), cudaMemcpyHostToDevice);
	
	delete m;
	delete[]blocks;
}
void cuda_download(Matrix*lm, Matrix*rm)
{
	cudaMemcpy(lm, rm, sizeof(Matrix), cudaMemcpyDeviceToHost);
	
	Block*blocks=new Block[NB*NB];
	cudaMemcpy(blocks, lm->p, sizeof(Block)*NB*NB, cudaMemcpyDeviceToHost);
	cudaFree(lm->p);
	
	lm->p=blocks;
#ifdef CONTIGUOUS
	for(int i=0;i<NB;++i){
		for(int j=0;j<NB;++j){
			float*p=new float[B*B];
			cudaMemcpy(p, lm->getBlock(i,j).p, sizeof(float)*B*B, cudaMemcpyDeviceToHost);
			cudaFree(lm->getBlock(i,j).p);
			lm->getBlock(i,j).p=p;
		}
	}
#else
	float*p=new float[B*B*NB*NB];
	cudaMemcpy(p, lm->getBlock(0,0).p, sizeof(float)*B*B*NB*NB, cudaMemcpyDeviceToHost);
	cudaFree(lm->getBlock(0,0).p);
	for(int i=0;i<NB;++i){
		for(int j=0;j<NB;++j){
			lm->getBlock(i,j).p=p+B*B*(i*NB+j);
		}
	}
#endif
}
#endif

int main(int argc, char**argv)
{
	if(argc<=3){
		usage(argv[0]);
		return -1;
	}
	N=atoi(argv[1]);
	P=atoi(argv[2]);
	B=atoi(argv[3]);
	if(N==0||P==0||B==0){
		usage(argv[0]);
		return -1;
	}
	ftime(&main_t1);
	NB=N/B;
	A=new Matrix(N,B);
	A->p=new Block[NB*NB];
	int i,j;
#ifdef CONTIGUOUS
	for(i=0;i<NB;++i){
		for(j=0;j<NB;++j){
			A->getBlock(i,j).b=B;
			A->getBlock(i,j).p=new float[B*B];
		}
	}
#else
	float*p=new float[B*B*NB*NB];
	for(i=0;i<NB;++i){
		for(j=0;j<NB;++j){
			A->getBlock(i,j).b=B;
			A->getBlock(i,j).p=p+B*B*(i*NB+j);
		}
	}
#endif
	srand48(1);
#define MAXRAND 32768.0
	for(i=0;i<N;++i){
		for(j=0;j<N;++j){
			A->at(i,j)=((double)lrand48())/MAXRAND;
			if(i==j){
				A->at(i,j)*=10;
			}
		}
	}

#ifdef __CUDACC__
	//CUDA code begins
	Matrix*d_A;
	if(cudaMalloc((void **)&d_A, sizeof(Matrix))!=cudaSuccess)
		throw runtime_error("cudaMalloc");
	cuda_upload(d_A,A);

	ftime(&threads_t1);
	thread_main<<<1,P>>>(d_A,P);
	cudaDeviceSynchronize();
	ftime(&threads_t2);

#ifdef CONTIGUOUS
	for(i=0;i<NB;++i){
		for(j=0;j<NB;++j){
			delete[] A->getBlock(i,j).p;
		}
	}
#else
	delete[] A->getBlock(0,0).p;
#endif
	delete[]A->p;

	cuda_download(A,d_A);
	//CUDA code ends
#else
	//pthread code begins
#ifdef GRAPHITE
	CarbonEnableModels();
#endif
	pthread_barrier_init(&barrier,NULL,P);
	int*thread_args=new int[P];
	pthread_t*thread_handle=new pthread_t[P];
	ftime(&threads_t1);
	for(i=1;i<P;++i){
		thread_args[i]=i;
		pthread_create(&thread_handle[i],NULL,thread_main,&thread_args[i]);
	}
	thread_args[0]=0;
	thread_main(&thread_args[0]);
	for(i=1;i<P;++i){
		pthread_join(thread_handle[i],NULL);
	}
	ftime(&threads_t2);
	delete[]thread_args;
	delete[]thread_handle;
	pthread_barrier_destroy(&barrier);
#ifdef GRAPHITE
	CarbonDisableModels();
#endif
	//pthread code ends
#endif
#ifndef GRAPHITE
	//A->print();
#endif

#ifdef CONTIGUOUS
	for(i=0;i<NB;++i){
		for(j=0;j<NB;++j){
			delete[]A->getBlock(i,j).p;
		}
	}
#else
	delete[]A->getBlock(0,0).p;
#endif
	delete[]A->p;
	delete A;
	ftime(&main_t2);
	cout<<"Overall execution time = "<<diffftime(main_t2,main_t1)<<endl;
	cout<<"Threads execution time = "<<diffftime(threads_t2,threads_t1)<<endl;
	return 0;
}
