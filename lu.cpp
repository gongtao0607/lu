#include <iostream>
#include <fstream>
#include <pthread.h>
#include <stdexcept>
#include "pthread_barrier_osx.h"
using namespace std;
int N,P,B,NB;
class Block{
public:
	float*p;
	Block(){
		p=new float[B*B];
	}
	float& at(int x,int y){
		if(0<=x&&x<B&&0<=y&&y<B){
			return p[x*B+y];
		}else{
			throw range_error("Block::at");
		}
	}
	~Block(){
		delete[]p;
	}
};
class Matrix{
public:
	Block*p;
	Matrix(){
		p=new Block[NB*NB];
	}
	Block& getBlock(int x,int y){
		if(0<=x&&x<NB&&0<=y&&y<NB){
			return p[x*NB+y];
		}else{
			throw range_error("Matrix::getBlock");
		}
	}
	float& at(int x,int y){
		if(0<=x&&x<N&&0<=y&&y<N){
			return getBlock(x/B,y/B).at(x%B,y%B);
		}else{
			throw range_error("Matrix::at");
		}
	}
	void print(){
		for(int i=0;i<N;++i){
			for(int j=0;j<N;++j){
				cout<<at(i,j)<<" ";
			}
			cout<<endl;
		}
	}
	~Matrix(){
		delete[]p;
	}
}*A;
pthread_barrier_t barrier;
void usage(char*n){
	cout<<"Usage: ./"<<n<<" N P B matrix_file\n\tN:NxN matrix\n\tP:P threads\n\tB:BxB block"<<endl;
}

// block b, referce block r, line "i" in b, line "k" in r, start column j, alpha
void daxpy(Block&b , Block&r, int i, int k, int j, float alpha)
{
	for (int p = j; p<B; p++)     b.at(i,p) += alpha*r.at(k,p);
}
void top_left(Block&b)
{
	float alpha;
	for (int k=0; k<B; k++) {
		/* modify subsequent columns */
		for (int i=k+1; i<B; i++) {
			b.at(i,k)/= b.at(k,k);
			alpha = -b.at(i,k);
			//length = n-k-1;
			daxpy(b, b, i, k, k+1, alpha);
		}
	}
}


void top_right(Block&b, Block&r)
{
	float alpha;
	for (int k=0; k<B; k++) {
		for (int i=k+1; i<B; i++) {
			alpha = -r.at(i,k);
			daxpy(b, b, i, k, 0, alpha);
		}
	}
}


void bottom_left(Block &b, Block&r)
{
	float alpha;
	for (int k=0; k<B; k++)
		for (int i=0; i<B; i++) {
			b.at(i,k) /= r.at(k,k);
			alpha = -b.at(i,k);
			daxpy(b, r, i, k, k+1, alpha);
		}
}


void bottom_right(Block &b, Block&r1, Block&r2)
{
	float alpha;
	for (int k=0; k<B; k++) {
		for (int i=0; i<B; i++) {
			alpha = -r1.at(i,k);
			daxpy(b,r2,i,k,0,alpha);
		}
	}
}

void* thread_main(void*p)
{
	int thread_id=*(int*)p;
	//pthread_barrier_wait(&barrier);
	for(int round=0;round<NB;++round){
		//step 1, calculate top left
		if(thread_id==0){
			//A->getBlock(round,round);
			top_left(A->getBlock(round,round));
		}
		pthread_barrier_wait(&barrier);
		//step 2, bottom left and top right
		//x 0 2
		//1 x x
		//3 x x
		//0,1,2,3->()
		for(int i=thread_id;i<(NB-round-1)*2;i+=P){
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
		pthread_barrier_wait(&barrier);
		//step 3, bottom right
		//x x x
		//x 0 1
		//x 2 3
		for(int i=thread_id;i<(NB-round-1)*(NB-round-1);i+=P){
			//A->getBlock(i/(NB-round-1)+round+1,i%(NB-round-1)+round+1)
			bottom_right(A->getBlock(i/(NB-round-1)+round+1,i%(NB-round-1)+round+1),
				A->getBlock(i/(NB-round-1)+round+1,round),
				A->getBlock(round,i%(NB-round-1)+round+1));
		}
		pthread_barrier_wait(&barrier);
	}
	return NULL;
}
int main(int argc, char**argv)
{
	if(argc<=4){
		usage(argv[0]);
		return -1;
	}
	N=atoi(argv[1]);
	P=atoi(argv[2]);
	B=atoi(argv[3]);
	ifstream fin(argv[4]);
	if(N==0||P==0||B==0){
		usage(argv[0]);
		return -1;
	}
	NB=N/B;
	A=new Matrix();
	int i,j;
	for(i=0;i<N;++i){
		for(j=0;j<N;++j){
			fin>>A->at(i,j);
		}
	}
	pthread_barrier_init(&barrier,NULL,P);
	int*thread_args=new int[P];
	pthread_t*thread_handle=new pthread_t[P];
	for(i=1;i<P;++i){
		thread_args[i]=i;
		pthread_create(&thread_handle[i],NULL,thread_main,&thread_args[i]);
	}
	thread_args[0]=0;
	thread_main(&thread_args[0]);
	for(i=1;i<P;++i){
		pthread_join(thread_handle[i],NULL);
	}
	delete[]thread_args;
	delete[]thread_handle;
	pthread_barrier_destroy(&barrier);
	A->print();
	
	return 0;
}
