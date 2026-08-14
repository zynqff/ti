use std::panic::{catch_unwind, AssertUnwindSafe};
use ndarray::ArrayView2;

pub struct Df3State { inner: df3::tract::DfTract }

#[no_mangle]
pub extern "C" fn vt_df3_create(atten_lim_db:f32)->*mut Df3State {
    match catch_unwind(AssertUnwindSafe(|| {
        let rp = df3::tract::RuntimeParams::default_with_ch(1).with_atten_lim(atten_lim_db);
        let m = df3::tract::DfTract::new(df3::tract::DfParams::default(), &rp).expect("DFNet3 init failed");
        Box::into_raw(Box::new(Df3State { inner: m }))
    })) { Ok(p) => p, Err(_) => std::ptr::null_mut() }
}

#[no_mangle]
pub unsafe extern "C" fn vt_df3_frame_length(st:*const Df3State)->usize { st.as_ref().map(|s|s.inner.hop_size).unwrap_or(0) }

#[no_mangle]
pub unsafe extern "C" fn vt_df3_process_frame(st:*mut Df3State,input:*const f32,output:*mut f32)->f32 {
    if st.is_null() || input.is_null() || output.is_null() { return f32::NAN; }
    let s=&mut *st; let n=s.inner.hop_size;
    let inp=std::slice::from_raw_parts(input,n); let out=std::slice::from_raw_parts_mut(output,n);
    let a=ArrayView2::from_shape((1,n),inp).unwrap(); let mut b=ndarray::Array2::<f32>::zeros((1,n));
    match s.inner.process(a,b.view_mut()) { Ok(v)=>{out.copy_from_slice(b.as_slice().unwrap());v}, Err(_)=>f32::NAN }
}

#[no_mangle]
pub unsafe extern "C" fn vt_df3_reset(st:*mut Df3State) { if !st.is_null(){(*st).inner.init().ok();} }

#[no_mangle]
pub unsafe extern "C" fn vt_df3_free(st:*mut Df3State) { if !st.is_null(){drop(Box::from_raw(st));} }
