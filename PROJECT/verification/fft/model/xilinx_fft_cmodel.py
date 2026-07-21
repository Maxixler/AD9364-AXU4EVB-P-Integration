"""Python adapter helpers for the Xilinx FFT v9.1 bit-accurate C model."""

from __future__ import annotations

import ctypes
from dataclasses import dataclass
import os
from pathlib import Path

import numpy as np


_LIBRARY_RELATIVE_PATH = Path(
    "win64/tools/fft_v9_1/libIp_xfft_v9_1_bitacc_cmodel.dll"
)
_FFT_SIZE = 2048
_NFFT = 11
_Q15_SCALE = 1 << 15


class _Generics(ctypes.Structure):
    _fields_ = [
        ("C_NFFT_MAX", ctypes.c_int),
        ("C_ARCH", ctypes.c_int),
        ("C_HAS_NFFT", ctypes.c_int),
        ("C_USE_FLT_PT", ctypes.c_int),
        ("C_INPUT_WIDTH", ctypes.c_int),
        ("C_TWIDDLE_WIDTH", ctypes.c_int),
        ("C_HAS_SCALING", ctypes.c_int),
        ("C_HAS_BFP", ctypes.c_int),
        ("C_HAS_ROUNDING", ctypes.c_int),
    ]


class _Inputs(ctypes.Structure):
    _fields_ = [
        ("nfft", ctypes.c_int),
        ("xn_re", ctypes.POINTER(ctypes.c_double)),
        ("xn_re_size", ctypes.c_int),
        ("xn_im", ctypes.POINTER(ctypes.c_double)),
        ("xn_im_size", ctypes.c_int),
        ("scaling_sch", ctypes.POINTER(ctypes.c_int)),
        ("scaling_sch_size", ctypes.c_int),
        ("direction", ctypes.c_int),
    ]


class _Outputs(ctypes.Structure):
    _fields_ = [
        ("xk_re", ctypes.POINTER(ctypes.c_double)),
        ("xk_re_size", ctypes.c_int),
        ("xk_im", ctypes.POINTER(ctypes.c_double)),
        ("xk_im_size", ctypes.c_int),
        ("blk_exp", ctypes.c_int),
        ("overflow", ctypes.c_int),
    ]


@dataclass(frozen=True)
class FftResult:
    """Natural-order signed Q1.15 FFT result returned by the official model."""

    real: np.ndarray
    imag: np.ndarray
    overflow: bool


def decode_scale_schedule(encoded: int, nfft: int) -> tuple[int, ...]:
    """Decode two-bit streaming FFT stage shifts, least-significant stage first."""

    stage_count = (nfft + 1) // 2
    return tuple((encoded >> (2 * stage)) & 0x3 for stage in range(stage_count))


def discover_xfft_library() -> Path:
    """Find the installed Vivado/Vitis FFT v9.1 bit-accurate model DLL."""

    roots = [os.environ.get("XILINX_VIVADO"), os.environ.get("XILINX_VITIS")]
    roots.append(r"C:\Xilinx\Vivado\2020.1")

    for root in roots:
        if not root:
            continue
        candidate = Path(root) / _LIBRARY_RELATIVE_PATH
        if candidate.is_file():
            return candidate

    raise FileNotFoundError(
        "Xilinx FFT v9.1 bit-accurate C-model library was not found under "
        "XILINX_VIVADO, XILINX_VITIS, or C:\\Xilinx\\Vivado\\2020.1"
    )


def _validated_samples(values: np.ndarray, component: str) -> np.ndarray:
    samples = np.asarray(values)
    if samples.ndim != 1 or samples.size != _FFT_SIZE:
        raise ValueError(f"{component} must contain exactly 2048 samples")
    if not np.issubdtype(samples.dtype, np.integer):
        raise ValueError(f"{component} samples must be signed 16-bit integers")
    if np.any(samples < -32768) or np.any(samples > 32767):
        raise ValueError(f"{component} samples must be within the signed 16-bit range")
    return np.ascontiguousarray(samples, dtype=np.int16)


def _load_model() -> ctypes.CDLL:
    library_path = discover_xfft_library()
    directory_handles = []
    if hasattr(os, "add_dll_directory"):
        directory_handles.append(os.add_dll_directory(str(library_path.parent)))
        vivado_root = library_path.parents[3]
        vivado_library_dir = vivado_root / "lib" / "win64.o"
        if vivado_library_dir.is_dir():
            directory_handles.append(os.add_dll_directory(str(vivado_library_dir)))

    try:
        model = ctypes.CDLL(str(library_path))
    finally:
        for handle in directory_handles:
            handle.close()
    model.xilinx_ip_xfft_v9_1_get_default_generics.argtypes = []
    model.xilinx_ip_xfft_v9_1_get_default_generics.restype = _Generics
    model.xilinx_ip_xfft_v9_1_create_state.argtypes = [_Generics]
    model.xilinx_ip_xfft_v9_1_create_state.restype = ctypes.c_void_p
    model.xilinx_ip_xfft_v9_1_destroy_state.argtypes = [ctypes.c_void_p]
    model.xilinx_ip_xfft_v9_1_destroy_state.restype = None
    model.xilinx_ip_xfft_v9_1_bitacc_simulate.argtypes = [
        ctypes.c_void_p,
        _Inputs,
        ctypes.POINTER(_Outputs),
    ]
    model.xilinx_ip_xfft_v9_1_bitacc_simulate.restype = ctypes.c_int
    return model


def _model_output_to_q15(values: np.ndarray, component: str) -> np.ndarray:
    scaled = np.asarray(values, dtype=np.float64) * _Q15_SCALE
    rounded = np.rint(scaled)
    if not np.all(np.isfinite(scaled)) or not np.array_equal(scaled, rounded):
        raise RuntimeError(f"Xilinx FFT {component} output is not on the Q1.15 grid")
    if np.any(rounded < -32768) or np.any(rounded > 32767):
        raise RuntimeError(
            f"Xilinx FFT {component} output is outside the signed 16-bit range"
        )
    return rounded.astype(np.int16)


def simulate_fft(
    i: np.ndarray,
    q: np.ndarray,
    scale_schedule: int = 0x6AB,
) -> FftResult:
    """Run one 2048-point forward FFT and return natural-order Q1.15 values."""

    i_samples = _validated_samples(i, "I")
    q_samples = _validated_samples(q, "Q")
    if not isinstance(scale_schedule, int) or not 0 <= scale_schedule < (1 << 12):
        raise ValueError("scale schedule must encode exactly six stages")
    decoded_schedule = decode_scale_schedule(scale_schedule, nfft=_NFFT)
    if decoded_schedule[-1] > 1:
        raise ValueError("final stage shift must be 0 or 1 for an odd streaming NFFT")
    real_input = np.ascontiguousarray(i_samples, dtype=np.float64) / _Q15_SCALE
    imag_input = np.ascontiguousarray(q_samples, dtype=np.float64) / _Q15_SCALE
    schedule = np.ascontiguousarray(decoded_schedule, dtype=np.int32)
    real_output = np.empty(_FFT_SIZE, dtype=np.float64)
    imag_output = np.empty(_FFT_SIZE, dtype=np.float64)

    model = _load_model()
    generics = model.xilinx_ip_xfft_v9_1_get_default_generics()
    generics.C_NFFT_MAX = _NFFT
    generics.C_ARCH = 3
    generics.C_HAS_NFFT = 0
    generics.C_USE_FLT_PT = 0
    generics.C_INPUT_WIDTH = 16
    generics.C_TWIDDLE_WIDTH = 24
    generics.C_HAS_SCALING = 1
    generics.C_HAS_BFP = 0
    generics.C_HAS_ROUNDING = 1

    state = model.xilinx_ip_xfft_v9_1_create_state(generics)
    if not state:
        raise RuntimeError("Xilinx FFT C model could not create simulation state")

    inputs = _Inputs(
        nfft=_NFFT,
        xn_re=real_input.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        xn_re_size=_FFT_SIZE,
        xn_im=imag_input.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        xn_im_size=_FFT_SIZE,
        scaling_sch=schedule.ctypes.data_as(ctypes.POINTER(ctypes.c_int)),
        scaling_sch_size=schedule.size,
        direction=1,
    )
    outputs = _Outputs(
        xk_re=real_output.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        xk_re_size=_FFT_SIZE,
        xk_im=imag_output.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        xk_im_size=_FFT_SIZE,
        blk_exp=0,
        overflow=0,
    )

    try:
        status = model.xilinx_ip_xfft_v9_1_bitacc_simulate(
            state, inputs, ctypes.byref(outputs)
        )
    finally:
        model.xilinx_ip_xfft_v9_1_destroy_state(state)

    if status != 0:
        raise RuntimeError(f"Xilinx FFT C model failed with status {status}")
    if outputs.xk_re_size != _FFT_SIZE or outputs.xk_im_size != _FFT_SIZE:
        raise RuntimeError("Xilinx FFT C model returned an incomplete transform")

    return FftResult(
        real=_model_output_to_q15(real_output, "real"),
        imag=_model_output_to_q15(imag_output, "imaginary"),
        overflow=bool(outputs.overflow),
    )
