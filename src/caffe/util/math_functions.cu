#include <math_functions.h>  // CUDA's, not caffe's, for fabs, signbit
#include <thrust/device_vector.h>
#include <thrust/functional.h>  // thrust::plus
#include <thrust/reduce.h>

#include <cmath>

#include "caffe/common.hpp"
#include "caffe/util/math_functions.hpp"

namespace caffe {
template <> 
void showDevice<float>(const float*data,int count)
{
    float *show=(float*)malloc(count*sizeof(float));
    cudaMemcpy(show,data,count*sizeof(float),cudaMemcpyDeviceToHost);
    for(int i=0;i<count;i++)
    {
        std::cout<<show[i]<<" ";
        if(i%10==9)std::cout <<std::endl;
    }
	std::cout<<std::endl;
    free(show);
}
template <> 
void showDevice<double>(const double*data,int count)
{
    double *show=(double*)malloc(count*sizeof(double));
    cudaMemcpy(show,data,count*sizeof(double),cudaMemcpyDeviceToHost);
    for(int i=0;i<count;i++)
    {
        std::cout<<show[i]<<" ";
        if(i%10==9)std::cout <<std::endl;
    }
	std::cout<<std::endl;
    free(show);
}
template <> 
void showDevice<signed char>(const signed char*data,int count)
{
    signed char *show=(signed char*)malloc(count*sizeof(signed char));
    cudaMemcpy(show,data,count*sizeof(signed char),cudaMemcpyDeviceToHost);
    for(int i=0;i<count;i++)
    {
        std::cout<<(int)show[i]<<" ";
        if(i%10==9)std::cout <<std::endl;
    }
	std::cout<<std::endl;
    free(show);
}
template <> 
void showDevice<int>(const int*data,int count)
{
    int *show=(int*)malloc(count*sizeof(int));
    cudaMemcpy(show,data,count*sizeof(int),cudaMemcpyDeviceToHost);
    for(int i=0;i<count;i++)
    {
        std::cout<<show[i]<<" ";
        if(i%10==9)std::cout <<std::endl;
    }
	std::cout<<std::endl;
    free(show);
}


//N是大矩阵的数量
__global__ void _copy_Data(int N, const signed char*dataIn, signed char*dataOut, int row, int col, int newRow, int newCol)
{
	//dataIn1  : m*k
	//dataIn2  : n*k
	//dataOut1 : m*newK
	//dataOut2 : newN*newK
	CUDA_KERNEL_LOOP(idx,N){
		int i = idx / newCol;
		int j = idx % newCol;
		if(i>=row || j>=col)  dataOut[idx]=0;
		else 
		{
			int pos = j+i*col;
			dataOut[idx] = dataIn[pos];			
		}
	}
}

//N是大矩阵的数量
__global__ void _copy_Data_back(int N, int*dataIn, int*dataOut, int row, int col, int newRow, int newCol)
{
	//dataIn1  : m*k
	//dataIn2  : n*k
	//dataOut1 : m*newK
	//dataOut2 : newN*newK
	CUDA_KERNEL_LOOP(idx,N){
		int i = idx / newCol;
		int j = idx % newCol;
		if(i>=row || j>=col)  continue;
		else 
		{
			int pos = j+i*col;
			dataIn[idx] = dataOut[pos];			
		}
	}
}

template <>
void caffe_gpu_copy<float>(const int n, const float* x, float* y)
{
    cublasScopy(Caffe::cublas_handle(),n,x,1,y,1);
}

template <>
void caffe_gpu_copy<double>(const int n, const double* x, double* y)
{
    cublasDcopy(Caffe::cublas_handle(),n,x,1,y,1);
}

template <typename Dtype>
__global__ void quantizeK_kernel(const int n, const Dtype* x, Dtype* y,const Dtype quantizeK)
{
  CUDA_KERNEL_LOOP(index, n) {
      if(quantizeK<1.01)
      {
          y[index] = x[index]>0? 1.0:-1.0;
      }
      else
      {
          y[index] = 2*round(x[index]*quantizeK)/quantizeK-1;
      }
  }
}

template <>
void caffe_gpu_quantizeK<float>(const int n, const float* x, float* y,const float quantizeK)
{
    quantizeK_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(
      n, x, y, quantizeK);
}

template <>
void caffe_gpu_quantizeK<double>(const int n, const double* x, double* y,const double quantizeK)
{
    quantizeK_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(
      n, x, y, quantizeK);
}

template <typename Dtype>
__global__ void int2Dtype_kernel(const int n, const int* x, Dtype* y, const Dtype unit_scale)
{
  CUDA_KERNEL_LOOP(index, n) {
    y[index]=Dtype(x[index])*unit_scale;
  }
}
template<>
void int2Dtype<float>(int n ,const int*data, float*out, const float unit_scale)
{
  int2Dtype_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, data, out, unit_scale);
}
template<>
void int2Dtype<double>(int n ,const int*data, double*out, const double unit_scale)
{
  int2Dtype_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, data, out, unit_scale);
}

template <typename Dtype>
__global__ void im2col_1x1_gpu_quantized_kernel(const int n, const Dtype* x, signed char* y, const Dtype t1, const Dtype t2, const Dtype unit_scale)
{
  CUDA_KERNEL_LOOP(index, n) {
          if(x[index]<t1)
          {
            y[index] = (-127);
          }
          else if(x[index]>t2)
          {
            y[index] = (127);
          }
          else
          {
            y[index] = (signed char)(round(x[index]*unit_scale));
          }
  }
}
template<>
void im2col_1x1_gpu_quantized<float>(int n, const float*data, signed char*out, const float t1, const float t2, const float unit_scale)
{
    im2col_1x1_gpu_quantized_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, data, out, t1, t2, unit_scale);
}
template<>
void im2col_1x1_gpu_quantized<double>(int n, const double*data, signed char*out, const double t1, const double t2, const double unit_scale)
{
    im2col_1x1_gpu_quantized_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(n, data, out, t1, t2, unit_scale);
}


template <typename Dtype>
__global__ void clipByValue_kernel(const int n, const Dtype* x, Dtype* y)
{
  CUDA_KERNEL_LOOP(index, n) {
      //Dtype newData = tanh(x[index]*20)*0.5+0.5;
      //y[index]=newData;
      Dtype newData = x[index]*0.5+0.5;
      y[index]=newData>0.0?(newData<1.0?newData:1.0):(0.0);
  }
}
template<>
void caffe_gpu_clipByValue<float>(const int n, const float* x, float* y)
{
    clipByValue_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(
      n, x, y);
}
template<>
void caffe_gpu_clipByValue<double>(const int n, const double* x, double* y)
{
    clipByValue_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(
      n, x, y);
}

template <typename Dtype>
__global__ void clipByValue_grad_kernel(const int n, const Dtype* diff,const Dtype* old_weight, Dtype* y)
{
  CUDA_KERNEL_LOOP(index, n) {
      //Dtype newData = tanh(x[index]*20);
      //y[index]=1-newData*newData;
      Dtype this_difference = old_weight[index]<1.0?(old_weight[index]>-1.0?1.0:0.0):(0.0);
      y[index]=this_difference*diff[index];
  }
}
template<>
void caffe_gpu_clipByValue_grad<float>(const int n, const float* diff,const float* old_weight, float* y)
{
    clipByValue_grad_kernel<float><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(
      n, diff, old_weight, y);
}
template<>
void caffe_gpu_clipByValue_grad<double>(const int n, const double* diff,const double* old_weight, double* y)
{
    clipByValue_grad_kernel<double><<<CAFFE_GET_BLOCKS(n), CAFFE_CUDA_NUM_THREADS>>>(
      n, diff, old_weight, y);
}

template <typename Dtype>
__global__ void caffe_gpu_quantize_nobias_kernel(const int n, const Dtype* fp32weights, signed char*int8weight, const float minT, const float maxT, const float unit_scale)
{
  CUDA_KERNEL_LOOP(index, n) {
    if(fp32weights[index]<minT)
    {
      int8weight[index]=-127;
    }
    else if(fp32weights[index]>maxT)
    {
      int8weight[index]=127;
    }
    else
    {
      int8weight[index]=round(fp32weights[index]*unit_scale);
    }
  }
}
template<>
void caffe_gpu_quantize_nobias<float>(const int count, const float*fp32weights, signed char*int8weight, const float minT, const float maxT, const float unit_scale)
{
  caffe_gpu_quantize_nobias_kernel<float><<<CAFFE_GET_BLOCKS(count), CAFFE_CUDA_NUM_THREADS>>>(
      count, fp32weights, int8weight, minT, maxT, unit_scale);
}
template<>
void caffe_gpu_quantize_nobias<double>(const int count, const double*fp32weights, signed char*int8weight, const double minT, const double maxT, const double unit_scale)
{
  caffe_gpu_quantize_nobias_kernel<double><<<CAFFE_GET_BLOCKS(count), CAFFE_CUDA_NUM_THREADS>>>(
      count, fp32weights, int8weight, minT, maxT, unit_scale);
}

void caffe_gpu_iGemm(const CBLAS_TRANSPOSE TransA,
    const CBLAS_TRANSPOSE TransB, const int M, const int N, const int K,
    const int alpha, const signed char* A, const signed char* B, const int beta,
    int* C)
{
    int lda = (TransA == CblasNoTrans) ? K : M;
  int ldb = (TransB == CblasNoTrans) ? N : K;
  cublasOperation_t cuTransA =
      (TransA == CblasNoTrans) ? CUBLAS_OP_N : CUBLAS_OP_T;
  cublasOperation_t cuTransB =
      (TransB == CblasNoTrans) ? CUBLAS_OP_N : CUBLAS_OP_T;
  CUBLAS_CHECK(cublasGemmEx(Caffe::cublas_handle(), cuTransB, cuTransA,
      N, M, K, &alpha, B, CUDA_R_8I, ldb, A, CUDA_R_8I, lda, &beta, C, CUDA_R_32I, N, CUDA_R_32I, CUBLAS_GEMM_DFALT));
}



template<typename Dtype>
__global__ void getMaxMin(int n, const Dtype*a, Dtype*max, Dtype*min)
{
  __shared__ Dtype maxTemp[CAFFE_CUDA_NUM_THREADS_FORMAXMIN];
  __shared__ Dtype minTemp[CAFFE_CUDA_NUM_THREADS_FORMAXMIN];
  maxTemp[threadIdx.x]=a[0];
  minTemp[threadIdx.x]=a[0];
  __syncthreads();
  
  int tid=threadIdx.x;
  while(tid<n)
  {
    if(a[tid]>maxTemp[threadIdx.x])
    {
      maxTemp[threadIdx.x]=a[tid];
    }
    if(a[tid]<minTemp[threadIdx.x])
    {
      minTemp[threadIdx.x]=a[tid];
    }
    tid+=blockDim.x;
  }
  __syncthreads();
  int i=CAFFE_CUDA_NUM_THREADS_FORMAXMIN/2;
  while(i!=0)
  {
    if(threadIdx.x<i)
    {
      maxTemp[threadIdx.x] = maxTemp[threadIdx.x]>maxTemp[threadIdx.x+i]?maxTemp[threadIdx.x]:maxTemp[threadIdx.x+i];
      minTemp[threadIdx.x] = minTemp[threadIdx.x]<minTemp[threadIdx.x+i]?minTemp[threadIdx.x]:minTemp[threadIdx.x+i];
    }
    i/=2;
  }
  __syncthreads();
  if(i==0 && threadIdx.x==0)
  {
    *max=maxTemp[0];
    *min=minTemp[0];
  }
}
template <>
void getMaxAndMIn<float>(int n, const float*data, float*max, float*min)
{
  getMaxMin<float><<<1,CAFFE_CUDA_NUM_THREADS_FORMAXMIN>>>(n,data,max,min);
}
template <>
void getMaxAndMIn<double>(int n, const double*data, double*max, double*min)
{
  getMaxMin<double><<<1,CAFFE_CUDA_NUM_THREADS_FORMAXMIN>>>(n,data,max,min);
}

template <>
void caffe_gpu_gemm<float>(const CBLAS_TRANSPOSE TransA,
    const CBLAS_TRANSPOSE TransB, const int M, const int N, const int K,
    const float alpha, const float* A, const float* B, const float beta,
    float* C) {
  // Note that cublas follows fortran order.
  int lda = (TransA == CblasNoTrans) ? K : M;
  int ldb = (TransB == CblasNoTrans) ? N : K;
  cublasOperation_t cuTransA =
      (TransA == CblasNoTrans) ? CUBLAS_OP_N : CUBLAS_OP_T;
  cublasOperation_t cuTransB =
      (TransB == CblasNoTrans) ? CUBLAS_OP_N : CUBLAS_OP_T;
  CUBLAS_CHECK(cublasSgemm(Caffe::cublas_handle(), cuTransB, cuTransA,
      N, M, K, &alpha, B, ldb, A, lda, &beta, C, N));
}

template <>
void caffe_gpu_gemm<double>(const CBLAS_TRANSPOSE TransA,
    const CBLAS_TRANSPOSE TransB, const int M, const int N, const int K,
    const double alpha, const double* A, const double* B, const double beta,
    double* C) {
  // Note that cublas follows fortran order.
  int lda = (TransA == CblasNoTrans) ? K : M;
  int ldb = (TransB == CblasNoTrans) ? N : K;
  cublasOperation_t cuTransA =
      (TransA == CblasNoTrans) ? CUBLAS_OP_N : CUBLAS_OP_T;
  cublasOperation_t cuTransB =
      (TransB == CblasNoTrans) ? CUBLAS_OP_N : CUBLAS_OP_T;
  CUBLAS_CHECK(cublasDgemm(Caffe::cublas_handle(), cuTransB, cuTransA,
      N, M, K, &alpha, B, ldb, A, lda, &beta, C, N));
}

template <>
void caffe_gpu_gemv<float>(const CBLAS_TRANSPOSE TransA, const int M,
    const int N, const float alpha, const float* A, const float* x,
    const float beta, float* y) {
  cublasOperation_t cuTransA =
      (TransA == CblasNoTrans) ? CUBLAS_OP_T : CUBLAS_OP_N;
  CUBLAS_CHECK(cublasSgemv(Caffe::cublas_handle(), cuTransA, N, M, &alpha,
      A, N, x, 1, &beta, y, 1));
}

template <>
void caffe_gpu_gemv<double>(const CBLAS_TRANSPOSE TransA, const int M,
    const int N, const double alpha, const double* A, const double* x,
    const double beta, double* y) {
  cublasOperation_t cuTransA =
      (TransA == CblasNoTrans) ? CUBLAS_OP_T : CUBLAS_OP_N;
  CUBLAS_CHECK(cublasDgemv(Caffe::cublas_handle(), cuTransA, N, M, &alpha,
      A, N, x, 1, &beta, y, 1));
}

template <>
void caffe_gpu_axpy<float>(const int N, const float alpha, const float* X,
    float* Y) {
  CUBLAS_CHECK(cublasSaxpy(Caffe::cublas_handle(), N, &alpha, X, 1, Y, 1));
}

template <>
void caffe_gpu_axpy<double>(const int N, const double alpha, const double* X,
    double* Y) {
  CUBLAS_CHECK(cublasDaxpy(Caffe::cublas_handle(), N, &alpha, X, 1, Y, 1));
}

void caffe_gpu_memcpy(const size_t N, const void* X, void* Y) {
  if (X != Y) {
    CUDA_CHECK(cudaMemcpy(Y, X, N, cudaMemcpyDefault));  // NOLINT(caffe/alt_fn)
  }
}

template <>
void caffe_gpu_scal<float>(const int N, const float alpha, float *X) {
  CUBLAS_CHECK(cublasSscal(Caffe::cublas_handle(), N, &alpha, X, 1));
}

template <>
void caffe_gpu_scal<double>(const int N, const double alpha, double *X) {
  CUBLAS_CHECK(cublasDscal(Caffe::cublas_handle(), N, &alpha, X, 1));
}

template <>
void caffe_gpu_axpby<float>(const int N, const float alpha, const float* X,
    const float beta, float* Y) {
  caffe_gpu_scal<float>(N, beta, Y);
  caffe_gpu_axpy<float>(N, alpha, X, Y);
}

template <>
void caffe_gpu_axpby<double>(const int N, const double alpha, const double* X,
    const double beta, double* Y) {
  caffe_gpu_scal<double>(N, beta, Y);
  caffe_gpu_axpy<double>(N, alpha, X, Y);
}

template <>
void caffe_gpu_dot<float>(const int n, const float* x, const float* y,
    float* out) {
  CUBLAS_CHECK(cublasSdot(Caffe::cublas_handle(), n, x, 1, y, 1, out));
}

template <>
void caffe_gpu_dot<double>(const int n, const double* x, const double* y,
    double * out) {
  CUBLAS_CHECK(cublasDdot(Caffe::cublas_handle(), n, x, 1, y, 1, out));
}

template <>
void caffe_gpu_asum<float>(const int n, const float* x, float* y) {
  CUBLAS_CHECK(cublasSasum(Caffe::cublas_handle(), n, x, 1, y));
}

template <>
void caffe_gpu_asum<double>(const int n, const double* x, double* y) {
  CUBLAS_CHECK(cublasDasum(Caffe::cublas_handle(), n, x, 1, y));
}

template <>
void caffe_gpu_scale<float>(const int n, const float alpha, const float *x,
                            float* y) {
  CUBLAS_CHECK(cublasScopy(Caffe::cublas_handle(), n, x, 1, y, 1));
  CUBLAS_CHECK(cublasSscal(Caffe::cublas_handle(), n, &alpha, y, 1));
}

template <>
void caffe_gpu_scale<double>(const int n, const double alpha, const double *x,
                             double* y) {
  CUBLAS_CHECK(cublasDcopy(Caffe::cublas_handle(), n, x, 1, y, 1));
  CUBLAS_CHECK(cublasDscal(Caffe::cublas_handle(), n, &alpha, y, 1));
}

template <typename Dtype>
__global__ void set_kernel(const int n, const Dtype alpha, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = alpha;
  }
}

template <typename Dtype>
void caffe_gpu_set(const int N, const Dtype alpha, Dtype* Y) {
  if (alpha == 0) {
    CUDA_CHECK(cudaMemset(Y, 0, sizeof(Dtype) * N));  // NOLINT(caffe/alt_fn)
    return;
  }
  // NOLINT_NEXT_LINE(whitespace/operators)
  set_kernel<Dtype><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, alpha, Y);
}

template void caffe_gpu_set<int>(const int N, const int alpha, int* Y);
template void caffe_gpu_set<float>(const int N, const float alpha, float* Y);
template void caffe_gpu_set<double>(const int N, const double alpha, double* Y);

template <typename Dtype>
__global__ void add_scalar_kernel(const int n, const Dtype alpha, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] += alpha;
  }
}

template <>
void caffe_gpu_add_scalar(const int N, const float alpha, float* Y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  add_scalar_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, alpha, Y);
}

template <>
void caffe_gpu_add_scalar(const int N, const double alpha, double* Y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  add_scalar_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, alpha, Y);
}

template <typename Dtype>
__global__ void add_kernel(const int n, const Dtype* a,
    const Dtype* b, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = a[index] + b[index];
  }
}

template <>
void caffe_gpu_add<float>(const int N, const float* a, const float* b,
    float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  add_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <>
void caffe_gpu_add<double>(const int N, const double* a, const double* b,
    double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  add_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <typename Dtype>
__global__ void sub_kernel(const int n, const Dtype* a,
    const Dtype* b, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = a[index] - b[index];
  }
}

template <>
void caffe_gpu_sub<float>(const int N, const float* a, const float* b,
    float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  sub_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <>
void caffe_gpu_sub<double>(const int N, const double* a, const double* b,
    double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  sub_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <typename Dtype>
__global__ void mul_kernel(const int n, const Dtype* a,
    const Dtype* b, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = a[index] * b[index];
  }
}

template <>
void caffe_gpu_mul<float>(const int N, const float* a,
    const float* b, float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  mul_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <>
void caffe_gpu_mul<double>(const int N, const double* a,
    const double* b, double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  mul_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <typename Dtype>
__global__ void div_kernel(const int n, const Dtype* a,
    const Dtype* b, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = a[index] / b[index];
  }
}

template <>
void caffe_gpu_div<float>(const int N, const float* a,
    const float* b, float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  div_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <>
void caffe_gpu_div<double>(const int N, const double* a,
    const double* b, double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  div_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, b, y);
}

template <typename Dtype>
__global__ void abs_kernel(const int n, const Dtype* a, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = abs(a[index]);
  }
}

template <>
void caffe_gpu_abs<float>(const int N, const float* a, float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  abs_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, y);
}

template <>
void caffe_gpu_abs<double>(const int N, const double* a, double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  abs_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, y);
}


template <typename Dtype>
__global__ void exp_kernel(const int n, const Dtype* a, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = exp(a[index]);
  }
}

template <>
void caffe_gpu_exp<float>(const int N, const float* a, float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  exp_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, y);
}

template <>
void caffe_gpu_exp<double>(const int N, const double* a, double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  exp_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, y);
}

template <typename Dtype>
__global__ void log_kernel(const int n, const Dtype* a, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = log(a[index]);
  }
}

template <>
void caffe_gpu_log<float>(const int N, const float* a, float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  log_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, y);
}

template <>
void caffe_gpu_log<double>(const int N, const double* a, double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  log_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, y);
}

template <typename Dtype>
__global__ void powx_kernel(const int n, const Dtype* a,
    const Dtype alpha, Dtype* y) {
  CUDA_KERNEL_LOOP(index, n) {
    y[index] = pow(a[index], alpha);
  }
}

template <>
void caffe_gpu_powx<float>(const int N, const float* a,
    const float alpha, float* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  powx_kernel<float><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, alpha, y);
}

template <>
void caffe_gpu_powx<double>(const int N, const double* a,
    const double alpha, double* y) {
  // NOLINT_NEXT_LINE(whitespace/operators)
  powx_kernel<double><<<CAFFE_GET_BLOCKS(N), CAFFE_CUDA_NUM_THREADS>>>(
      N, a, alpha, y);
}

DEFINE_AND_INSTANTIATE_GPU_UNARY_FUNC(sign, y[index] = (Dtype(0) < x[index])
                                      - (x[index] < Dtype(0)));
DEFINE_AND_INSTANTIATE_GPU_UNARY_FUNC(sgnbit, y[index] = signbit(x[index]));

void caffe_gpu_rng_uniform(const int n, unsigned int* r) {
  CURAND_CHECK(curandGenerate(Caffe::curand_generator(), r, n));
}

template <>
void caffe_gpu_rng_uniform<float>(const int n, const float a, const float b,
                                  float* r) {
  CURAND_CHECK(curandGenerateUniform(Caffe::curand_generator(), r, n));
  const float range = b - a;
  if (range != static_cast<float>(1)) {
    caffe_gpu_scal(n, range, r);
  }
  if (a != static_cast<float>(0)) {
    caffe_gpu_add_scalar(n, a, r);
  }
}

template <>
void caffe_gpu_rng_uniform<double>(const int n, const double a, const double b,
                                   double* r) {
  CURAND_CHECK(curandGenerateUniformDouble(Caffe::curand_generator(), r, n));
  const double range = b - a;
  if (range != static_cast<double>(1)) {
    caffe_gpu_scal(n, range, r);
  }
  if (a != static_cast<double>(0)) {
    caffe_gpu_add_scalar(n, a, r);
  }
}

template <>
void caffe_gpu_rng_gaussian(const int n, const float mu, const float sigma,
                            float* r) {
  CURAND_CHECK(
      curandGenerateNormal(Caffe::curand_generator(), r, n, mu, sigma));
}

template <>
void caffe_gpu_rng_gaussian(const int n, const double mu, const double sigma,
                            double* r) {
  CURAND_CHECK(
      curandGenerateNormalDouble(Caffe::curand_generator(), r, n, mu, sigma));
}

}  // namespace caffe
