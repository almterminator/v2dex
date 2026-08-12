#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LOG_TAG "V2DexHevJNI"

typedef int (*hev_main_from_file_fn)(const char *config_path, int tun_fd);
typedef void (*hev_quit_fn)(void);
typedef void (*hev_stats_fn)(uint64_t *tx_packets,
                             uint64_t *tx_bytes,
                             uint64_t *rx_packets,
                             uint64_t *rx_bytes);

static pthread_mutex_t core_mutex = PTHREAD_MUTEX_INITIALIZER;
static void *core_handle = NULL;
static hev_main_from_file_fn core_main_from_file = NULL;
static hev_quit_fn core_quit = NULL;
static hev_stats_fn core_stats = NULL;

typedef struct {
  char *config_path;
  int tun_fd;
} tunnel_args_t;

static pthread_mutex_t state_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_t tunnel_thread;
static int tunnel_thread_started = 0;
static int tunnel_running = 0;

static int core_library_path(char *buffer, size_t buffer_size) {
  Dl_info info;
  if (dladdr((void *)&core_library_path, &info) == 0 || info.dli_fname == NULL) {
    return 0;
  }

  const char *slash = strrchr(info.dli_fname, '/');
  if (slash == NULL) {
    return snprintf(buffer, buffer_size, "libhev-socks5-tunnel-core.so") > 0;
  }

  size_t dir_len = (size_t)(slash - info.dli_fname + 1);
  const char *name = "libhev-socks5-tunnel-core.so";
  size_t name_len = strlen(name);
  if (dir_len + name_len + 1 > buffer_size) {
    return 0;
  }

  memcpy(buffer, info.dli_fname, dir_len);
  memcpy(buffer + dir_len, name, name_len + 1);
  return 1;
}

static int load_core(void) {
  pthread_mutex_lock(&core_mutex);
  if (core_handle != NULL) {
    pthread_mutex_unlock(&core_mutex);
    return 1;
  }

  char path[1024];
  const char *core_path =
      core_library_path(path, sizeof(path)) ? path : "libhev-socks5-tunnel-core.so";
  core_handle = dlopen(core_path, RTLD_NOW | RTLD_LOCAL);
  if (core_handle == NULL) {
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "dlopen core failed: %s", dlerror());
    pthread_mutex_unlock(&core_mutex);
    return 0;
  }

  core_main_from_file =
      (hev_main_from_file_fn)dlsym(core_handle, "hev_socks5_tunnel_main_from_file");
  core_quit = (hev_quit_fn)dlsym(core_handle, "hev_socks5_tunnel_quit");
  core_stats = (hev_stats_fn)dlsym(core_handle, "hev_socks5_tunnel_stats");

  if (core_main_from_file == NULL || core_quit == NULL || core_stats == NULL) {
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "dlsym core API failed: %s", dlerror());
    dlclose(core_handle);
    core_handle = NULL;
    core_main_from_file = NULL;
    core_quit = NULL;
    core_stats = NULL;
    pthread_mutex_unlock(&core_mutex);
    return 0;
  }

  pthread_mutex_unlock(&core_mutex);
  return 1;
}

static void *run_tunnel(void *data) {
  tunnel_args_t *args = (tunnel_args_t *)data;

  pthread_mutex_lock(&state_mutex);
  tunnel_running = 1;
  pthread_mutex_unlock(&state_mutex);

  core_main_from_file(args->config_path, args->tun_fd);

  pthread_mutex_lock(&state_mutex);
  tunnel_running = 0;
  tunnel_thread_started = 0;
  pthread_mutex_unlock(&state_mutex);

  free(args->config_path);
  free(args);
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_hev_htproxy_TProxyService_TProxyStartService(JNIEnv *env,
                                                  jobject thiz,
                                                  jstring config_path,
                                                  jint fd) {
  (void)thiz;

  const char *path = (*env)->GetStringUTFChars(env, config_path, NULL);
  if (path == NULL) {
    return JNI_FALSE;
  }

  if (!load_core()) {
    (*env)->ReleaseStringUTFChars(env, config_path, path);
    return JNI_FALSE;
  }

  pthread_mutex_lock(&state_mutex);
  if (tunnel_thread_started) {
    pthread_mutex_unlock(&state_mutex);
    (*env)->ReleaseStringUTFChars(env, config_path, path);
    return JNI_TRUE;
  }
  pthread_mutex_unlock(&state_mutex);

  tunnel_args_t *args = (tunnel_args_t *)calloc(1, sizeof(tunnel_args_t));
  if (args == NULL) {
    (*env)->ReleaseStringUTFChars(env, config_path, path);
    return JNI_FALSE;
  }

  args->config_path = strdup(path);
  args->tun_fd = fd;
  (*env)->ReleaseStringUTFChars(env, config_path, path);

  if (args->config_path == NULL) {
    free(args);
    return JNI_FALSE;
  }

  pthread_mutex_lock(&state_mutex);
  tunnel_thread_started = 1;
  pthread_mutex_unlock(&state_mutex);

  if (pthread_create(&tunnel_thread, NULL, run_tunnel, args) != 0) {
    pthread_mutex_lock(&state_mutex);
    tunnel_thread_started = 0;
    tunnel_running = 0;
    pthread_mutex_unlock(&state_mutex);
    free(args->config_path);
    free(args);
    return JNI_FALSE;
  }

  return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_hev_htproxy_TProxyService_TProxyStopService(JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  pthread_mutex_lock(&state_mutex);
  int should_join = tunnel_thread_started;
  pthread_t thread = tunnel_thread;
  pthread_mutex_unlock(&state_mutex);

  if (!should_join) {
    return JNI_TRUE;
  }

  if (load_core()) {
    core_quit();
  }
  pthread_join(thread, NULL);
  return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_hev_htproxy_TProxyService_TProxyIsRunning(JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  pthread_mutex_lock(&state_mutex);
  int running = tunnel_running;
  pthread_mutex_unlock(&state_mutex);
  return running ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlongArray JNICALL
Java_hev_htproxy_TProxyService_TProxyGetStats(JNIEnv *env, jobject thiz) {
  (void)thiz;

  uint64_t tx_packets = 0;
  uint64_t tx_bytes = 0;
  uint64_t rx_packets = 0;
  uint64_t rx_bytes = 0;
  if (load_core()) {
    core_stats(&tx_packets, &tx_bytes, &rx_packets, &rx_bytes);
  }

  jlong values[4] = {
      (jlong)tx_packets,
      (jlong)tx_bytes,
      (jlong)rx_packets,
      (jlong)rx_bytes,
  };

  jlongArray result = (*env)->NewLongArray(env, 4);
  if (result != NULL) {
    (*env)->SetLongArrayRegion(env, result, 0, 4, values);
  }

  return result;
}
