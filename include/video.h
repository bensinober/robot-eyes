#ifndef _OPENCV3_VIDEO_H_
#define _OPENCV3_VIDEO_H_

#ifdef __cplusplus
#include <opencv2/opencv.hpp>
#include <opencv2/video.hpp>
extern "C" {
#endif

#include "core.h"

#ifdef __cplusplus
typedef cv::Ptr<cv::BackgroundSubtractorMOG2>* BackgroundSubtractorMOG2;
typedef cv::Ptr<cv::BackgroundSubtractorKNN>* BackgroundSubtractorKNN;
typedef cv::Ptr<cv::Tracker>* Tracker;
typedef cv::Ptr<cv::TrackerMIL>* TrackerMIL;
typedef cv::Ptr<cv::TrackerGOTURN>* TrackerGOTURN;
typedef cv::Ptr<cv::TrackerNano>* TrackerNano;
typedef cv::Ptr<cv::TrackerVit>* TrackerVit;

typedef cv::KalmanFilter* KalmanFilter;
typedef cv::TrackerVit::Params* TrackerVit_Params;
#else
typedef void* BackgroundSubtractorMOG2;
typedef void* BackgroundSubtractorKNN;
typedef void* Tracker;
typedef void* TrackerMIL;
typedef void* TrackerGOTURN;
typedef void* KalmanFilter;
typedef void* TrackerNano;
typedef void* TrackerVit;
typedef void* TrackerVit_Params;
#endif

BackgroundSubtractorMOG2 BackgroundSubtractorMOG2_Create();
BackgroundSubtractorMOG2 BackgroundSubtractorMOG2_CreateWithParams(int history, double varThreshold, bool detectShadows);
void BackgroundSubtractorMOG2_Close(BackgroundSubtractorMOG2 b);
void BackgroundSubtractorMOG2_Apply(BackgroundSubtractorMOG2 b, Mat src, Mat dst);

BackgroundSubtractorKNN BackgroundSubtractorKNN_Create();
BackgroundSubtractorKNN BackgroundSubtractorKNN_CreateWithParams(int history, double dist2Threshold, bool detectShadows);

void BackgroundSubtractorKNN_Close(BackgroundSubtractorKNN b);
void BackgroundSubtractorKNN_Apply(BackgroundSubtractorKNN b, Mat src, Mat dst);

void CalcOpticalFlowPyrLK(Mat prevImg, Mat nextImg, Mat prevPts, Mat nextPts, Mat status, Mat err);
void CalcOpticalFlowPyrLKWithParams(Mat prevImg, Mat nextImg, Mat prevPts, Mat nextPts, Mat status, Mat err, Size winSize, int maxLevel, TermCriteria criteria, int flags, double minEigThreshold);
void CalcOpticalFlowFarneback(Mat prevImg, Mat nextImg, Mat flow, double pyrScale, int levels,
                              int winsize, int iterations, int polyN, double polySigma, int flags);

double FindTransformECC(Mat templateImage, Mat inputImage, Mat warpMatrix, int motionType, TermCriteria criteria, Mat inputMask, int gaussFiltSize);

bool Tracker_Init(Tracker self, Mat image, Rect boundingBox);
bool Tracker_Update(Tracker self, Mat image, Rect* boundingBox);
float Tracker_GetTrackingScore(Tracker self);

TrackerMIL TrackerMIL_Create();
void TrackerMIL_Close(TrackerMIL self);

KalmanFilter KalmanFilter_New(int dynamParams, int measureParams);
KalmanFilter KalmanFilter_NewWithParams(int dynamParams, int measureParams, int controlParams, int type);
void KalmanFilter_Close(KalmanFilter kf);

void KalmanFilter_Init(KalmanFilter kf, int dynamParams, int measureParams);
void KalmanFilter_InitWithParams(KalmanFilter kf, int dynamParams, int measureParams, int controlParams, int type);
Mat KalmanFilter_Predict(KalmanFilter kf);
Mat KalmanFilter_PredictWithParams(KalmanFilter kf, Mat control);
Mat KalmanFilter_Correct(KalmanFilter kf, Mat measurement);

Mat KalmanFilter_GetStatePre(KalmanFilter kf);
Mat KalmanFilter_GetStatePost(KalmanFilter kf);
Mat KalmanFilter_GetTransitionMatrix(KalmanFilter kf);
Mat KalmanFilter_GetControlMatrix(KalmanFilter kf);
Mat KalmanFilter_GetMeasurementMatrix(KalmanFilter kf);
Mat KalmanFilter_GetProcessNoiseCov(KalmanFilter kf);
Mat KalmanFilter_GetMeasurementNoiseCov(KalmanFilter kf);
Mat KalmanFilter_GetErrorCovPre(KalmanFilter kf);
Mat KalmanFilter_GetGain(KalmanFilter kf);
Mat KalmanFilter_GetErrorCovPost(KalmanFilter kf);
Mat KalmanFilter_GetTemp1(KalmanFilter kf);
Mat KalmanFilter_GetTemp2(KalmanFilter kf);
Mat KalmanFilter_GetTemp3(KalmanFilter kf);
Mat KalmanFilter_GetTemp4(KalmanFilter kf);
Mat KalmanFilter_GetTemp5(KalmanFilter kf);

void KalmanFilter_SetStatePre(KalmanFilter kf, Mat statePre);
void KalmanFilter_SetStatePost(KalmanFilter kf, Mat statePost);
void KalmanFilter_SetTransitionMatrix(KalmanFilter kf, Mat transitionMatrix);
void KalmanFilter_SetControlMatrix(KalmanFilter kf, Mat controlMatrix);
void KalmanFilter_SetMeasurementMatrix(KalmanFilter kf, Mat measurementMatrix);
void KalmanFilter_SetProcessNoiseCov(KalmanFilter kf, Mat processNoiseCov);
void KalmanFilter_SetMeasurementNoiseCov(KalmanFilter kf, Mat measurementNoiseCov);
void KalmanFilter_SetErrorCovPre(KalmanFilter kf, Mat errorCovPre);
void KalmanFilter_SetGain(KalmanFilter kf, Mat gain);
void KalmanFilter_SetErrorCovPost(KalmanFilter kf, Mat errorCovPost);

// https://github.com/HonglinChu/SiamTrackers/tree/master/NanoTrack/models/nanotrackv2
TrackerNano TrackerNano_Create();
void TrackerNano_Close(TrackerNano self);

// https://github.com/opencv/opencv_zoo/tree/main/models/object_tracking_vittrack
TrackerVit TrackerVit_Create();
TrackerVit TrackerVit_CreateWithParams(const char* model, int backend, int target, Scalar meanvalue, Scalar stdvalue);
void TrackerVit_Close(TrackerVit self);
bool TrackerVit_init(TrackerVit self, Mat image, Rect boundingBox);
bool TrackerVit_Update(TrackerVit self, Mat image, Rect* boundingBox);
float TrackerVit_GetTrackingScore(TrackerVit self);

#ifdef __cplusplus
}
#endif

#endif //_OPENCV3_VIDEO_H_
