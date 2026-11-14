/* miniz_export.h - generated in the upstream release archive; written here
 * because the upstream repository does not track it. Behaviour matches the
 * generated file (static build: no visibility decorations). */
#ifndef MINIZ_EXPORT_H
#define MINIZ_EXPORT_H

#if defined(_WIN32) && defined(MINIZ_DLL)
#ifdef MINIZ_DLL_EXPORTS
#define MINIZ_EXPORT __declspec(dllexport)
#else
#define MINIZ_EXPORT __declspec(dllimport)
#endif
#elif defined(__GNUC__) && defined(MINIZ_DLL)
#define MINIZ_EXPORT __attribute__((visibility("default")))
#else
#define MINIZ_EXPORT
#endif

#endif /* MINIZ_EXPORT_H */
