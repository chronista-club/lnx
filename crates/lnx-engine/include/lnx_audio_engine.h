#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <ostream>
#include <new>

enum class LNXNodeType {
  Input = 0,
  Output = 1,
  Mixer = 2,
  Effect = 3,
  Generator = 4,
  Analyzer = 5,
};

struct LNXAudioEngine;

extern "C" {

LNXAudioEngine *lnx_engine_create();

void lnx_engine_destroy(LNXAudioEngine *engine);

int lnx_engine_initialize(LNXAudioEngine *engine);

int lnx_engine_start(LNXAudioEngine *engine);

int lnx_engine_stop(LNXAudioEngine *engine);

int lnx_engine_is_running(LNXAudioEngine *engine);

unsigned int lnx_engine_get_sample_rate(LNXAudioEngine *engine);

unsigned int lnx_engine_get_buffer_size(LNXAudioEngine *engine);

int lnx_engine_set_buffer_size(LNXAudioEngine *engine, unsigned int size);

unsigned int lnx_graph_add_node(LNXAudioEngine *engine, LNXNodeType node_type, const char *name);

int lnx_graph_remove_node(LNXAudioEngine *engine, unsigned int node_id);

unsigned int lnx_graph_connect_nodes(LNXAudioEngine *engine,
                                     unsigned int _source_node,
                                     unsigned int _source_channel,
                                     unsigned int _dest_node,
                                     unsigned int _dest_channel);

int lnx_graph_disconnect(LNXAudioEngine *engine, unsigned int _connection_id);

int lnx_node_set_gain(LNXAudioEngine *engine, unsigned int _node_id, float _gain);

int lnx_node_set_pan(LNXAudioEngine *engine, unsigned int _node_id, float _pan);

int lnx_node_set_enabled(LNXAudioEngine *engine, unsigned int _node_id, int _enabled);

int lnx_effect_set_parameter(LNXAudioEngine *engine,
                             unsigned int _node_id,
                             const char *param_name,
                             float _value);

int lnx_effect_get_parameter(LNXAudioEngine *engine,
                             unsigned int _node_id,
                             const char *param_name,
                             float *value);

int lnx_device_select_input(LNXAudioEngine *engine, const char *device_name);

int lnx_device_select_output(LNXAudioEngine *engine, const char *device_name);

void lnx_free_string(char *s);

int lnx_engine_process_messages(LNXAudioEngine *engine);

}  // extern "C"
