use ndarray::ArrayView2;
use std::ffi::CString;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Mutex;

pub struct Df3State {
    inner: df3::tract::DfTract,
}

// Holds the human-readable reason the last create/process call failed.
// The original code used `catch_unwind(...) { Err(_) => null_mut() }`,
// which discards the panic payload entirely -- there was no way, even for
// the developer, to see *why* DfTract::new() panicked. This captures the
// panic message + source location via a temporary panic hook and stores it
// here so it can be read from Swift through vt_df3_last_error().
static LAST_ERROR: Mutex<Option<CString>> = Mutex::new(None);

fn set_last_error(msg: String) {
    let safe = msg.replace('\0', " ");
    let c = CString::new(safe)
        .unwrap_or_else(|_| CString::new("DFNet3 error (unprintable message)").unwrap());
    if let Ok(mut slot) = LAST_ERROR.lock() {
        *slot = Some(c);
    }
}

fn clear_last_error() {
    if let Ok(mut slot) = LAST_ERROR.lock() {
        *slot = None;
    }
}

fn panic_message(info: &std::panic::PanicHookInfo) -> String {
    let payload = if let Some(s) = info.payload().downcast_ref::<&str>() {
        s.to_string()
    } else if let Some(s) = info.payload().downcast_ref::<String>() {
        s.clone()
    } else {
        "unknown panic payload".to_string()
    };
    let location = info
        .location()
        .map(|l| format!(" at {}:{}", l.file(), l.line()))
        .unwrap_or_default();
    format!("{}{}", payload, location)
}

#[no_mangle]
pub extern "C" fn vt_df3_create(atten_lim_db: f32) -> *mut Df3State {
    clear_last_error();

    // Temporarily install a hook that records the panic message/location
    // before catch_unwind's Err(_) arm would otherwise throw it away.
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|info| {
        set_last_error(format!("DFNet3 init panicked: {}", panic_message(info)));
    }));

    let result = catch_unwind(AssertUnwindSafe(|| {
        let rp = df3::tract::RuntimeParams::default_with_ch(1).with_atten_lim(atten_lim_db);
        let m = df3::tract::DfTract::new(df3::tract::DfParams::default(), &rp)
            .expect("DFNet3 init failed");
        Box::into_raw(Box::new(Df3State { inner: m }))
    }));

    std::panic::set_hook(previous_hook);

    match result {
        Ok(p) => p,
        Err(_) => {
            // If the panic hook above didn't run for some reason (e.g. an
            // abort-on-panic build), make sure callers still see *something*
            // instead of a bare NULL with no explanation.
            if let Ok(mut slot) = LAST_ERROR.lock() {
                if slot.is_none() {
                    *slot = Some(
                        CString::new(
                            "DFNet3 init panicked (no message captured -- \
                             this build may be compiled with panic=abort, \
                             in which case the process likely crashed instead \
                             of returning here)",
                        )
                        .unwrap(),
                    );
                }
            }
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn vt_df3_frame_length(st: *const Df3State) -> usize {
    st.as_ref().map(|s| s.inner.hop_size).unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn vt_df3_process_frame(
    st: *mut Df3State,
    input: *const f32,
    output: *mut f32,
) -> f32 {
    if st.is_null() || input.is_null() || output.is_null() {
        set_last_error("vt_df3_process_frame called with a null pointer".to_string());
        return f32::NAN;
    }
    let s = &mut *st;
    let n = s.inner.hop_size;
    let inp = std::slice::from_raw_parts(input, n);
    let out = std::slice::from_raw_parts_mut(output, n);
    let a = match ArrayView2::from_shape((1, n), inp) {
        Ok(v) => v,
        Err(e) => {
            set_last_error(format!("DFNet3 process_frame: bad input shape: {}", e));
            return f32::NAN;
        }
    };
    let mut b = ndarray::Array2::<f32>::zeros((1, n));
    match s.inner.process(a, b.view_mut()) {
        Ok(v) => {
            out.copy_from_slice(b.as_slice().unwrap());
            v
        }
        Err(e) => {
            set_last_error(format!("DFNet3 process_frame failed: {}", e));
            f32::NAN
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn vt_df3_reset(st: *mut Df3State) {
    if !st.is_null() {
        if let Err(e) = (*st).inner.init() {
            set_last_error(format!("DFNet3 reset failed: {}", e));
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn vt_df3_free(st: *mut Df3State) {
    if !st.is_null() {
        drop(Box::from_raw(st));
    }
}

/// Returns the reason the last vt_df3_create()/vt_df3_process_frame()/
/// vt_df3_reset() call failed, or a null pointer if the last call succeeded.
#[no_mangle]
pub extern "C" fn vt_df3_last_error() -> *const c_char {
    if let Ok(slot) = LAST_ERROR.lock() {
        if let Some(ref c) = *slot {
            return c.as_ptr();
        }
    }
    std::ptr::null()
}

