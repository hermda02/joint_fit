program dust_fit
    use healpix_types
    use pix_tools
    use fitstools
    use udgrade_nr
    implicit none
  
    !------------------------------------------------------------------------------------------------------
    ! Daniel Herman 2020                                                                                  |
    !                                                                                                     |  
    ! This program fits the Planck (NPIPE) 353 GHz dust map to LFI bands to set constraints on the level  |
    ! of polarized emission from Anomalous Microwave Emission in the LFI bands.                           |
    !                                                                                                     |  
    !-----------------------------------------------------------------------------------------------------|  
  
    !-----------------------------------------------------------------------------------------------------|  
    ! What we want here: we are taking a joint fit of CMB, synchrotron, and dust emission. In order to do |
    ! effectively, this will be a mulit-frequency Gibbs sampler. Using the BeyondPlanck LFI maps, along   |
    ! side the WMAP data, we iteratively fit CMB (per pixel), synchrotron (per pixel), and dust (global). |
    ! Once this has been done, estimates to the level of AME polarization will be made using the lowest   |
    ! frequency bands used here.                                                                          |
    !-----------------------------------------------------------------------------------------------------|  
    
    ! Constants
    real(dp)           :: k_B     = 1.3806503d-23
    real(dp)           :: h       = 1.0545726691251021d-34 * 2.d0 * pi
    real(dp)           :: c       = 2.99792458d8
    real(dp)           :: T_CMB   = 2.7255d0
  
    integer(i4b)       :: i, j, k, l, iter, npix, nside, nmaps, ordering
    integer(i4b)       :: beta_samp_nside, nlheader, niter, nbands, iterations
    real(dp)           :: nullval
    real(dp)           :: missval = -1.6375d30
    logical(lgt)       :: anynull, double_precision, test, exist, output_fg
  
    character(len=128) :: dust_file, mask_file, arg1 !, synch_map, cmb_map
    character(len=128) :: mapfile, title, toit, direct
  
    real(dp), allocatable, dimension(:,:,:,:)    :: fg_amp, temp_amp
    real(dp), allocatable, dimension(:,:,:)      :: maps, rmss, model, res
    real(dp), allocatable, dimension(:,:,:)      :: dust_free, synch_free
    real(dp), allocatable, dimension(:,:,:)      :: synch_map, dust_map, cmb_map
    real(dp), allocatable, dimension(:,:)        :: dust_temp, synch_temp, cmb_temp, map, rms
    real(dp), allocatable, dimension(:,:)        :: beta_s, chi_map, mask
    real(dp), allocatable, dimension(:)          :: nuz
    real(dp)                                     :: nu_ref_s, nu_ref_d, beta_std, ki, ki_0, frq,a, sed
    character(len=80),  dimension(180)           :: header
    character(len=80),  dimension(3)             :: tqu
    character(len=80), allocatable, dimension(:) :: bands
    character(len=4)                             :: iter_str
  
    dust_file  = 'test_data/npipe6v20_353_map_QUADCOR_ZODICOR_DIPCOR_n0064_uK.fits'
    mask_file = '~/data/masks/mask_common_dx12_n0064.fits'
    tqu(1)    = 'T'
    tqu(2)    = 'Q'
    tqu(3)    = 'U'
    i         = getsize_fits(dust_file, nside=nside, ordering=ordering, nmaps=nmaps)
    npix      = nside2npix(nside) 
    nbands    = 11
    nlheader  = size(header)

    call getarg(1,arg1)
    direct = arg1

    !----------------------------------------------------------------------------------------------------------
    allocate(dust_temp(0:npix-1,nmaps), synch_temp(0:npix-1,nmaps), cmb_temp(0:npix-1,nmaps))
    allocate(maps(0:npix-1,nmaps,nbands), rmss(0:npix-1,nmaps,nbands), model(0:npix-1,nmaps,nbands))
    allocate(res(0:npix-1,nmaps,nbands),chi_map(0:npix-1,nmaps),mask(0:npix-1,1))
    allocate(fg_amp(0:npix-1,nmaps,nbands,3),temp_amp(0:npix-1,nmaps,nbands,3))
    allocate(dust_free(0:npix-1,nmaps,nbands), synch_free(0:npix-1,nmaps,nbands))
    allocate(cmb_map(0:npix-1,nmaps,nbands), dust_map(0:npix-1,nmaps,nbands), synch_map(0:npix-1,nmaps,nbands))
    allocate(nuz(nbands),beta_s(0:npix-1,nmaps),bands(nbands))
  
    allocate(map(0:npix-1,nmaps))
    allocate(rms(0:npix-1,nmaps))
    !----------------------------------------------------------------------------------------------------------
    !----------------------------------------------------------------------------------------------------------
    niter           = 25      ! # of MC-MC iterations
    iterations      = 100     ! # of iterations in the samplers
    nu_ref_s        = 70.1d0  ! Synchrotron reference frequency
    nu_ref_d        = 353.d0  ! Dust reference frequency
    beta_s          = -3.1d0  ! \beta_synch Gaussian prior mean
    beta_std        = 2.0d0   ! \beta_synch Gaussian prior std
    beta_samp_nside = 8       ! \beta_synch nside sampling
    output_fg       = .false. ! Option for outputting foregrounds for all bands
    test            = .true.  ! Testing Metropolis-Hasting apparatus
    !----------------------------------------------------------------------------------------------------------

    bands(1)  = ('bp_030_')
    bands(2)  = ('bp_044_')
    bands(3)  = ('bp_070ds1_')
    bands(4)  = ('bp_070ds2_')
    bands(5)  = ('bp_070ds3_')
    bands(6)  = ('wmap9_K_')
    bands(7)  = ('wmap9_Ka_')
    bands(8)  = ('wmap9_Q1_')
    bands(9)  = ('wmap9_Q2_')
    bands(10) = ('wmap9_V1_')
    bands(11) = ('wmap9_V2_')
    ! bands(12) = ('npipe6v20_143_')

    nuz(1)    = 28.4d0
    nuz(2)    = 44.1d0
    nuz(3)    = 70.1d0
    nuz(4)    = 70.1d0
    nuz(5)    = 70.1d0
    nuz(6)    = 22.8d0
    nuz(7)    = 33.d0
    nuz(8)    = 40.6d0
    nuz(9)    = 40.6d0
    nuz(10)   = 60.8d0
    nuz(11)   = 60.8d0
    ! nuz(12)   = 143.0d0

    !----------------------------------------------------------------------------------------------------------
    ! Read maps

    do j = 1, nbands
        call read_bintab('test_data/v4.00/' // trim(bands(j)) // 'rms_n0064.fits',rms,npix,nmaps,nullval,anynull,header=header)
        rmss(:,:,j) = rms
        call read_bintab('test_data/v4.00/' // trim(bands(j)) // 'map_n0064_60arcmin.fits', &
        map,npix,nmaps,nullval,anynull,header=header)
        maps(:,:,j) = map
    end do

    call read_bintab(dust_file,dust_temp,npix,nmaps,nullval,anynull,header=header)
    call read_bintab(mask_file,mask,npix,1,nullval,anynull,header=header)

    !----------------------------------------------------------------------------------------------------------
    ! Calculation portion
    !----------------------------------------------------------------------------------------------------------
    do k = 2, nmaps
        if (k == 1) then
            write(*,*) 'Sampling Temperature'
            write(*,*) '-----------------------'
        else if (k == 2) then
            write(*,*) 'Stokes Q'
            write(*,*) '-----------------------'
        else if (k == 3) then
            write(*,*) 'Stokes U'
            write(*,*) '-----------------------'
        end if 

        do iter = 1, niter
        
            write(*,*) 'Iteration', iter
            write(*,*) '-----------------------'
            write(*,*) ''


            write(*,*) 'Sampling dust amplitudes'
            do j = 1, nbands
                if (nuz(j) .gt. 70.d0) then
                    fg_amp(:,k,j,2)       = 0.7d0*dust_spec(nuz(j),19.6d0,1.53d0)/dust_spec(353.d0,19.6d0,1.53d0)
                    dust_map(:,k,j)       = fg_amp(:,k,j,2)*dust_temp(:,k)
                    ! if (iter == 1) then
                    !     write(iter_str, '(i0.4)') iter
                    !     title = trim(direct) // trim(bands(j)) // 'no_dust_' &
                    !          // trim(tqu(k)) // '_' // trim(iter_str) // '.fits'
                    !     call write_maps((maps(:,k,j) - dust_map(:,k,j)),npix,1,title)
                    ! end if
                else
                    fg_amp(:,k,j,2)       = temp_fit((maps(:,:,j)-synch_map(:,:,j)-cmb_map(:,:,j)),dust_temp(:,:),rmss(:,:,j),k)
                    dust_map(:,k,j)       = fg_amp(:,k,j,2)*dust_temp(:,k)
                end if
            end do
            write(*,*) 'Chi^2 ', compute_chisq(fg_amp,k)
            write(*,*) ''


            write(*,*) 'Sampling A_synch'
            temp_amp(:,k,3,1)         = sample_s_amp((maps-dust_map-cmb_map),fg_amp(:,:,3,1), rmss, k, 1)
        
            do i = 0, npix-1
                do j = 1, nbands
                    fg_amp(i,k,j,1)   = temp_amp(i,k,3,1)*compute_fg(1,nuz(j),beta_s(i,k))
                end do
            end do
            write(*,*) 'Chi^2 ', compute_chisq(fg_amp,k)
            write(*,*) ''

            beta_s(:,k)               = sample_beta((maps-dust_map-cmb_map), npix, k, beta_std, beta_s, beta_samp_nside)
            do i = 0, npix-1
                do j = 1, nbands
                    fg_amp(i,k,j,1)   = fg_amp(i,k,3,1)*compute_fg(1,nuz(j),beta_s(i,k))
                end do
            end do
            write(*,*) 'Mean synch beta: '
            write(*,*) sum(beta_s(:,k))/npix
            synch_map(:,k,:)          = fg_amp(:,k,:,1)
            write(*,*) 'Chi^2 ', compute_chisq(fg_amp,k)
            write(*,*) ''

            write(*,*) 'Sampling CMB amplitudes'

            temp_amp(:,k,3,3)         = sample_cmb((maps - synch_map - dust_map),fg_amp(:,:,3,3), rmss, k)

            do j = 1, nbands
                fg_amp(:,k,j,3)       = temp_amp(:,k,3,3)
            end do

            cmb_map                   = fg_amp(:,:,:,3)

            res                       = maps - synch_map - dust_map - cmb_map
        
            write(*,*) 'Chi^2 ', compute_chisq(fg_amp,k)
            write(*,*) ''

            toit = trim(direct) // 'dust_' // trim(tqu(k)) // '_amplitudes.dat'
            inquire(file=trim(direct) // 'dust_' // trim(tqu(k)) // '_amplitudes.dat',exist=exist)
            if (exist) then
                open(30,file = trim(direct) // 'dust_' // trim(tqu(k)) // '_amplitudes.dat', status="old", &
                               position="append", action="write")
            else
                open(30,file = trim(direct) // 'dust_' // trim(tqu(k)) // '_amplitudes.dat', status="new", action="write")
                ! write(30,'(12(A))') bands
            endif
            write(30,'(12(E17.8))') fg_amp(1,k,:,2)
            close(30)

            if (mod(iter,5) .EQ. 0) then

                write(iter_str, '(i0.4)') iter
                if (output_fg .eqv. .true.) then
                    do j = 1, nbands
                        title = trim(direct) // trim(bands(j)) // 'dust_fit_'// trim(tqu(k)) & 
                                // '_' // trim(iter_str) // '.fits'
                        call write_maps(dust_map(:,k,j),npix,1,title)
                        title = trim(direct) // trim(bands(j)) // 'synch_amplitude_' //  trim(tqu(k)) &
                                // '_' // trim(iter_str) // '.fits'
                        call write_maps(fg_amp(:,k,j,1),npix,1,title)
                        title = trim(direct) // trim(bands(j)) // 'cmb_amplitude_' //  trim(tqu(k)) &
                                // '_' // trim(iter_str) // '.fits'
                        call write_maps(fg_amp(:,k,j,3),npix,1,title)
                    end do
                else 
                    title = trim(direct) // trim(bands(3)) // 'synch_amplitude_' //  trim(tqu(k)) &
                            // '_' // trim(iter_str) // '.fits'
                    call write_maps(fg_amp(:,k,3,1),npix,1,title)
                    title = trim(direct) // trim(bands(3)) // 'cmb_amplitude_' //  trim(tqu(k)) &
                            // '_' // trim(iter_str) // '.fits'
                    call write_maps(fg_amp(:,k,3,3),npix,1,title)
                end if
                
                do j = 1, nbands
                    title = trim(direct) // trim(bands(j)) // 'residual_' // trim(tqu(k)) & 
                            // '_' // trim(iter_str) // '.fits'
                    call write_maps(res(:,k,j),npix,1,title)
                end do
                title = trim(direct) // 'synch_beta_' // trim(tqu(k)) // '_' // trim(iter_str) // '.fits'
                call write_maps(beta_s(:,k),npix,1,title)
                do i = 0, npix-1
                    do j = 1, nbands
                        chi_map(i,k) = chi_map(i,k) + (maps(i,k,j) - (synch_map(i,k,j) + &
                                       dust_map(i,k,j) + cmb_map(i,j,k)))**2.d0/rmss(i,k,j)**2.d0
                    end do
                end do
                chi_map(:,k) = chi_map(:,k)/(nbands+3)
                title = trim(direct) // 'chisq_' // trim(tqu(k)) // '_' // trim(iter_str) // '.fits'
                call write_maps(chi_map(:,k),npix,1,title)

            end if
        end do    
    end do
  
  contains

    !----------------------------------------------------------------------------------------------------------
    ! Functions and subroutines
    !----------------------------------------------------------------------------------------------------------
 
    function rand_normal(mean,stdev) result(c)
         double precision :: mean,stdev,c,temp(2),theta,r
         if (stdev <= 0.0d0) then
            write(*,*) "Standard Deviation must be positive."
         else
            call RANDOM_NUMBER(temp)
            r=(-2.0d0*log(temp(1)))**0.5
            theta = 2.0d0*PI*temp(2)
            c= mean+stdev*r*sin(theta)
      end if
    end function

    function sample_cmb(band,temp,rms,map_n)
        implicit none

        integer(i4b), intent(in)                        :: map_n
        real(dp), dimension(0:npix-1,nmaps), intent(in) :: temp
        real(dp), dimension(0:npix-1,nmaps,nbands), intent(in) :: band, rms
        real(dp)                                        :: x0, sum1, sum2, sed, amp
        real(dp)                                        :: chi_0, chi_00, chiz, new
        real(dp), dimension(nbands)                     :: x
        real(dp), dimension(0:npix-1,nmaps)             :: norm
        real(dp), dimension(0:npix-1,nmaps,nbands)      :: cov
        real(dp), dimension(0:npix-1)                   :: sample_cmb

        cov = rms*2

        do i = 0, npix-1
            sum1 = 0.d0
            sum2 = 0.d0
            do j = 1, nbands
                sed  = 1
                sum1 = sum1 + (band(i,map_n,j)*sed)*cov(i,map_n,j)
                sum2 = sum2 + (sed)**2.d0*cov(i,map_n,j)
                norm(i,map_n) = norm(i,map_n) + cov(i,map_n,j)*(sed)**2.d0
            end do
            norm(i,map_n) = norm(i,map_n)/nbands

            ! Allow negative amplitude in temperature.
            amp = sum1/sum2
            chi_00 = 0.d0
            do j = 1, nbands
                chi_00 = chi_00 + (band(i,map_n,j)-temp(i,map_n))**2.d0/cov(i,map_n,j)
            end do
            chi_0 = 0.d0
            do j = 1, nbands
                chi_0 = chi_0 + (band(i,map_n,j)-(sum1/sum2))**2.d0/cov(i,map_n,j)
            end do
            do l = 1, iterations
                chiz = 0.d0
                new = amp + rand_normal(0.d0,1.d0)/sqrt(norm(i,map_n))
                do j = 1, nbands
                    chiz = chiz + (band(i,map_n,j)-new)**2.d0/cov(i,map_n,j)
                end do
                if (chiz < chi_0) then
                    amp = new
                    chi_0 = chiz
                end if
            end do
            if (chi_0 < chi_00) then
                sample_cmb(i) = amp
            else
                sample_cmb(i) = temp(i,map_n)
            end if
            sample_cmb(i) = amp
        end do

    end function sample_cmb
  
    function temp_fit(band,temp,rms,map_n)
        implicit none
    
        integer(i4b), intent(in)            :: map_n
        real(dp), dimension(0:npix-1,nmaps) :: band, temp, rms, cov
        real(dp)                            :: temp_fit, norm, chiz
        real(dp)                            :: amplitude, amp, new
        real(dp)                            :: sum1, sum2, chi_0
    
        cov = rms*2
    
        ! Uncertainty, used for sampling.
        norm  = sum(cov(:,map_n)*temp(:,map_n)**2.d0)/sum(mask)
        
        sum1 = 0.d0
        sum2 = 0.d0
    
        do i=0,npix-1
            sum1   = sum1 + (band(i,map_n)*temp(i,map_n))*cov(i,map_n)*mask(i,1)
            sum2   = sum2 + temp(i,map_n)**2.d0*cov(i,map_n)*mask(i,1)
        end do

        if (sum1 < 0.d0) then
            amp = 0.d0
            write(*,*) bands(j)
            write(*,*) 'Negative Dust Amplitude'
        else
            amp   = sum1/sum2
            chi_0 = 0.d0
            do i = 0, npix-1
                chi_0 = chi_0 + (band(i,map_n)-amp*temp(i,map_n))**2.d0/cov(i,map_n)*mask(i,1)
            end do
    
            do l = 1, iterations
                chiz = 0.d0
                new = amp + rand_normal(0.d0,1.d0)/sqrt(norm)
                do i = 0, npix-1
                    chiz = chiz + (band(i,map_n)-new*temp(i,map_n))**2.d0/cov(i,map_n)*mask(i,1)
                end do
                if (chiz < chi_0) then
                    amp = new
                    chi_0 = chiz
                end if
            end do
        end if
        temp_fit  = amp
  
    end function temp_fit
  
    function sample_s_amp(band,A,rms,map_n,comm)
      implicit none
  
      integer(i4b),                               intent(in) :: map_n, comm
      real(dp), dimension(0:npix-1,nmaps),        intent(in) :: A
      real(dp), dimension(0:npix-1,nmaps,nbands), intent(in) :: band, rms
      real(dp)                                               :: sum1, sum2, powerl, chi_0, chi_00, ch
      real(dp)                                               :: amp, new, chiz, damp, fitval
      real(dp), dimension(0:npix-1,nmaps)                    :: norm
      real(dp), dimension(0:npix-1,nmaps,nbands)             :: cov
      real(dp), dimension(0:npix-1,nmaps,nbands,2)           :: trmp
      real(dp), dimension(0:npix-1)                          :: sample_s_amp
      integer(i4b)                                           :: fail

      cov = rms*2

      do i = 0, npix-1
        sum1 = 0.0d0
        sum2 = 0.0d0
        do j = 1, nbands
            powerl        = compute_fg(comm,nuz(j),beta_s(i,map_n))
            sum1          = sum1 + (band(i,map_n,j)*powerl)*cov(i,map_n,j)
            sum2          = sum2 + (powerl)**2.d0*cov(i,map_n,j)
            norm(i,map_n) = norm(i,map_n) + cov(i,map_n,j)*(powerl)**2.d0
        end do
        norm(i,map_n)     = norm(i,map_n)/nbands
        amp               = sum1/sum2

        ! Enforce positive amplitude for temperature.
        if (map_n == 1) then
            if (amp < 0.d0) then 
                amp = 0.d0
            end if
        end if
        sample_s_amp(i) = amp

        chi_00 = 0.d0
        do j = 1, nbands
            chi_00 = chi_00 + (band(i,map_n,j)-(A(i,map_n))*compute_fg(1,nuz(j),beta_s(i,map_n)))**2.d0/cov(i,map_n,j)
        end do
        chi_0 = 0.d0
        do j = 1, nbands
            chi_0 = chi_0 + (band(i,map_n,j)-(sum1/sum2)*compute_fg(1,nuz(j),beta_s(i,map_n)))**2.d0/cov(i,map_n,j)
        end do
        do l = 1, iterations
            chiz = 0.d0
            new = amp + rand_normal(0.d0,1.d0)/sqrt(norm(i,map_n))
            do j = 1, nbands
                chiz = chiz + (band(i,map_n,j)-(new*compute_fg(1,nuz(j),beta_s(i,map_n))))**2.d0/cov(i,map_n,j)
            end do
            if (chiz < chi_0) then
                amp = new
                chi_0 = chiz
            end if
        end do
        if (chi_0 < chi_00) then
            sample_s_amp(i) = amp
        else
            sample_s_amp(i) = A(i,map_n)
        end if
      end do
    end function sample_s_amp
  
    function sample_beta(band, npix, map_n, sigma, beta, nside2)
        
        ! Rewriting beta-sampler for estimating at lower nside.

        implicit none
  
        integer(i4b), intent(in)                               :: npix, map_n, nside2
        integer(i4b)                                           :: nside1, npix2
        real(dp), intent(in)                                   :: sigma
        real(dp), dimension(0:npix-1,nmaps,nbands), intent(in) :: band
        real(dp), dimension(0:npix-1,nmaps), intent(in)        :: beta
        real(dp), dimension(0:npix-1)                          :: sample_beta
        real(dp), dimension(0:npix-1,nmaps,nbands)             :: map2fit, cov
        real(dp), dimension(0:npix-1,nmaps)                    :: bet
        real(dp), allocatable, dimension(:,:,:)                :: band_low, fg_amp_low, rms_low
        real(dp), allocatable, dimension(:,:)                  :: beta_low
        real(dp), allocatable, dimension(:)                    :: sample_beta_low
        real(dp), dimension(nbands)                            :: signal, tmp
        real(dp), dimension(2)                                 :: x
        real(dp)                                               :: a, b, c, num, temp, r, p

        real(dp), dimension(iterations+1)                    :: chi, tump, accept, prob
        real(dp)                                             :: naccept    
        logical                                              :: exist

        bet     = beta
        map2fit = band
        cov     = rmss*rmss

        nside1 = npix2nside(npix)
        write(*,*) 'Sampling Beta at nside ', nside2
        if (nside1 == nside2) then
            npix2 = npix
        else
            npix2 = nside2npix(nside2)
        end if
        allocate(band_low(0:npix2-1,nmaps,nbands),fg_amp_low(0:npix2-1,nmaps,nbands))
        allocate(beta_low(0:npix2-1,nmaps),rms_low(0:npix2-1,nmaps,nbands))
        allocate(sample_beta_low(0:npix2-1))

        if (nside1 /= nside2) then 
            if (ordering == 1) then
                call udgrade_ring(bet,nside1,beta_low,nside2)
            else
                call udgrade_nest(bet,nside1,beta_low,nside2)
            end if
            do j = 1, nbands
                if (ordering == 1) then
                    call udgrade_ring(map2fit(:,:,j),nside1,band_low(:,:,j),nside2)
                    call convert_nest2ring(nside1,map2fit(:,:,j))
                    call udgrade_ring(fg_amp(:,:,j,1),nside1,fg_amp_low(:,:,j),nside2)
                    call convert_nest2ring(nside1,fg_amp(:,:,j,1))
                    call udgrade_ring(cov(:,:,j),nside1,rms_low(:,:,j),nside2)
                    call convert_nest2ring(nside1,rmss(:,:,j))
                else
                    call udgrade_nest(map2fit(:,:,j),nside1,band_low(:,:,j),nside2)
                    call udgrade_nest(fg_amp(:,:,j,1),nside1,fg_amp_low(:,:,j),nside2)
                    call udgrade_nest(rmss(:,:,j),nside1,rms_low(:,:,j),nside2)
                end if
            end do
            rms_low = sqrt(rms_low * (npix/npix2))
        else
            do j = 1, nbands
                band_low(:,:,j)   = band(:,:,j)
                fg_amp_low(:,:,j) = fg_amp(:,:,j,1)
                rms_low(:,:,j)    = rmss(:,:,j)
            end do
            beta_low = beta
        end if

        x(1) = 1.d0
        do i = 0, npix2-1
            a = 0.d0
            temp = beta_low(i,map_n)
            do j = 1, nbands
              a = a + (((fg_amp_low(i,map_n,j) * compute_fg(1,nuz(j),temp)) &
                    - band_low(i,map_n,j))**2.d0)/rms_low(i,map_n,j)**2
            end do
            c    = a/nbands

            if (test .eqv. .true.) then
                prob(1)   = 1.d0
                chi(1)    = a
                tump(1)   = temp
                accept(1) = 0.d0
                naccept   = 0
            end if

            do l = 1, iterations
                r = rand_normal(temp, sigma)
                b = 0.d0
                do j = 1, nbands
                    tmp(j) = fg_amp_low(i,map_n,j)*compute_fg(1,nuz(j),r)
                    b      = b + ((tmp(j)-band_low(i,map_n,j))**2.d0)/rms_low(i,map_n,j)**2.d0
                end do
                b = b/nbands

                if (b < c .and. r .lt. -2.5 .and. r .gt. -3.5) then
                    temp = r
                    c    = b
                    if (test .eqv. .true.) then
                        naccept  = naccept + 1
                        prob(l+1)= 1
                    end if
                else
                    x(2) = exp(0.5d0*(b-c))
                    p = minval(x)
                    call RANDOM_NUMBER(num)
                    if (num < p) then
                        if (r .lt. -2.5 .and. r .gt. -3.5) then
                            temp = r
                            c    = b
                            if (test .eqv. .true.) then
                                naccept = naccept + 1
                            end if
                        end if
                    end if
                    ! Metropolis testing apparatus
                    !-----------------------------
                    if (test .eqv. .true.) then
                        if (i == 600) then
                            prob(l+1)   = p
                        end if
                    end if
                end if
                if (test .eqv. .true.) then
                    if (i == 600) then 
                        chi(l+1)    = c
                        tump(l+1)   = temp
                        accept(l+1) = naccept/l
                    end if
                end if
                !-----------------------------
            end do
            ! Metropolis testing apparatus
            !-----------------------------
            if (test .eqv. .true.) then
                if (i == 600) then
                    inquire(file=trim(direct) // trim(tqu(k)) // '_prob.dat',exist=exist)
                    if (exist) then
                        open(40,file = trim(direct) // trim(tqu(k)) // '_prob.dat',&
                                       status="old", position="append", action="write")
                    else
                        open(40,file = trim(direct) // trim(tqu(k)) // '_prob.dat',&
                                       status="new", action="write")
                    endif
    
                    inquire(file=trim(direct) // trim(tqu(k)) // '_chi.dat',exist=exist)
                    if (exist) then
                        open(41,file = trim(direct) // trim(tqu(k)) // '_chi.dat',&
                                       status="old", position="append", action="write")
                    else
                        open(41,file = trim(direct) // trim(tqu(k)) // '_chi.dat',&
                                       status="new", action="write")
                    endif
    
                    inquire(file=trim(direct) // trim(tqu(k)) // '_temps.dat',exist=exist)
                    if (exist) then
                        open(42,file = trim(direct) // trim(tqu(k)) // '_temps.dat',&
                                       status="old", position="append", action="write")
                    else
                        open(42,file = trim(direct) // trim(tqu(k)) // '_temps.dat',&
                                       status="new", action="write")
                    endif
    
                    inquire(file=trim(direct) // trim(tqu(k)) // '_accept.dat',exist=exist)
                    if (exist) then
                        open(43,file = trim(direct) // trim(tqu(k)) // '_accept.dat',&
                                       status="old", position="append", action="write")
                    else
                        open(43,file = trim(direct) // trim(tqu(k)) // '_accept.dat',&
                                       status="new", action="write")
                    endif
    
                    do l = 1, iterations+1
                        write(40,*) prob(l)
                        write(41,*) chi(l)
                        write(42,*) tump(l)
                        write(43,*) accept(l)
                    end do
                    close(40)
                    close(41)
                    close(42)
                    close(43)
                end if
            end if
            !-----------------------------
            sample_beta_low(i) = temp
        end do

        if (nside1 /= nside2) then
            if (ordering == 1) then
                call udgrade_ring(sample_beta_low,nside2,sample_beta,nside1)
                call convert_nest2ring(nside2,sample_beta_low)
            else
                call udgrade_nest(sample_beta_low,nside2,sample_beta,nside1)
            end if
        else
            sample_beta = sample_beta_low
        end if

        deallocate(band_low)
        deallocate(fg_amp_low)
        deallocate(beta_low)
        deallocate(rms_low)
        deallocate(sample_beta_low)

    end function sample_beta
  
    subroutine write_maps(map,npix,nmap,title)
      implicit none
  
      integer(i4b), intent(in)       :: npix, nmap
      character(len=80), intent(in) :: title
      real(dp), dimension(npix,nmap) :: map
      call write_bintab(map, npix, nmap, header, nlheader, trim(title))

    end subroutine write_maps
  
    function compute_chisq(amp,map_n)
      use healpix_types
      implicit none
      real(dp), dimension(0:npix-1,nmaps,nbands,3), intent(in)   :: amp
      integer(i4b), intent(in)                                   :: map_n
      real(dp)                                                   :: compute_chisq, s, signal, chisq
      integer(i4b)                                               :: m,n
  
      chisq = 0.d0
      do m = 0, npix-1
        do n = 1, nbands
            s = 0.d0
            signal = (amp(m,map_n,n,1)*(compute_fg(1,nuz(n),beta_s(m,map_n))) &
                   + amp(m,map_n,n,2)*dust_temp(m,map_n) + amp(m,map_n,n,3))*mask(m,1)
            s = s + signal
            chisq = chisq + (((maps(m,map_n,n) - s)**2)/(rmss(m,map_n,n)**2))*mask(m,1)
        end do
      end do 
      compute_chisq = chisq/(sum(mask(:,1))+nbands+3) ! n-1 dof, npix + nbands + A_s + A_dust + A_cmb + \beta_s
  
    end function compute_chisq
  
    function compute_fg(comp,freq,param)
        implicit none
        integer(i4b), intent(in)           :: comp
        real(dp), intent(in)               :: freq, param
        real(dp)                           :: compute_fg, x, x0

        if (comp == 1) then
           compute_fg  = (freq/nu_ref_s)**param
        else if (comp == 2) then
           compute_fg = param
        end if
  
    end function compute_fg

    function dust_spec(nu,Td,betad)
        implicit none
        real(dp), intent(in) :: nu, Td, betad
        real(dp)             :: dust_spec, z, y
        real(dp)             :: bnu_prime, rj_cmb

        z = h / (k_B*Td)

        y = h*(nu*1.0d9) / (k_B*T_CMB)

        rj_cmb = ((exp(y)-1)**2.d0)/(y**2.d0*exp(y))

        dust_spec = rj_cmb*(exp(z*nu_ref_d*1d9)-1.d0) / (exp(z*nu*1d9)-1.d0) * (nu/nu_ref_d)**(betad+1.d0)

    end function dust_spec
  end program dust_fit