
#ifndef IRM_DLL_EXPORT_H
#define IRM_DLL_EXPORT_H

#ifdef IRM_DLL_STATIC_DEFINE
#  define IRM_DLL_EXPORT
#  define IRM_DLL_NO_EXPORT
#else
#  ifndef IRM_DLL_EXPORT
#    ifdef PhreeqcRM_EXPORTS
        /* We are building this library */
#      define IRM_DLL_EXPORT __attribute__((visibility("default")))
#    else
        /* We are using this library */
#      define IRM_DLL_EXPORT __attribute__((visibility("default")))
#    endif
#  endif

#  ifndef IRM_DLL_NO_EXPORT
#    define IRM_DLL_NO_EXPORT __attribute__((visibility("hidden")))
#  endif
#endif

#ifndef IRM_DLL_DEPRECATED
#  define IRM_DLL_DEPRECATED __attribute__ ((__deprecated__))
#endif

#ifndef IRM_DLL_DEPRECATED_EXPORT
#  define IRM_DLL_DEPRECATED_EXPORT IRM_DLL_EXPORT IRM_DLL_DEPRECATED
#endif

#ifndef IRM_DLL_DEPRECATED_NO_EXPORT
#  define IRM_DLL_DEPRECATED_NO_EXPORT IRM_DLL_NO_EXPORT IRM_DLL_DEPRECATED
#endif

/* NOLINTNEXTLINE(readability-avoid-unconditional-preprocessor-if) */
#if 0 /* DEFINE_NO_DEPRECATED */
#  ifndef IRM_DLL_NO_DEPRECATED
#    define IRM_DLL_NO_DEPRECATED
#  endif
#endif

#endif /* IRM_DLL_EXPORT_H */
