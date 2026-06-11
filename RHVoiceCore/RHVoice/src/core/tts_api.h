#ifndef RHVOICE_TTS_API_H
#define RHVOICE_TTS_API_H

#include <string>
#include <vector>
#include <memory>

namespace RHVoice {

    class TTSApi {
    public:
        TTSApi();
        ~TTSApi();

        // Initialize the TTS engine with a specific voice
        bool initialize(const std::string& voiceName);

        // Synthesize text to audio data
        std::vector<char> synthesize(const std::string& text);

        // Get a list of available voices
        std::vector<std::string> getAvailableVoices();

        // Set synthesis parameters (e.g., speed, pitch)
        bool setParameter(const std::string& paramName, const std::string& value);

    private:
        // Internal implementation details
        class Impl;
        std::unique_ptr<Impl> m_impl;
    };

} // namespace RHVoice

#endif // RHVOICE_TTS_API_H
