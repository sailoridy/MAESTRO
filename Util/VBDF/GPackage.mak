#fsources += LinAlg.f  !A BLAS backage shipped with BDF, for Maestro we prefer our own Util/BLAS
f90sources += bdf.f90

NEED_BLAS := t
NEED_LINPACK := t
