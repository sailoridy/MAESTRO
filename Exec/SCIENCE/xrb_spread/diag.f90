! xrb-specific diagnostic routine
!
! output files:
!
!    xrb_enuc_diag.out:
!        peak nuclear energy generation rate (erg / g / s)
!        x/y/z location of peak 
!        total mass of C12
!
!    xrb_temp_diag.out:
!        peak temperature in the helium layer
!            helium layer defined by X(He4) >= diag_define_he_layer where 
!            diag_define_he_layer is a xrb _parameter
!        x/y/z location of peak
!


module diag_module

  use bl_types
  use bl_IO_module
  use multifab_module
  use ml_layout_module
  use define_bc_module

  implicit none

  private

  public :: diag, flush_diag

contains

  subroutine diag(time,dt,dx,s,rho_Hnuc,rho_Hext,thermal,rho_omegadot, &
                  rho0,rhoh0,p0,tempbar, &
                  gamma1bar,div_coeff, &
                  u,w0,normal, &
                  mla,the_bc_tower)

    use bl_prof_module
    use bl_constants_module

    real(kind=dp_t), intent(in   ) :: dt,dx(:,:),time
    type(multifab) , intent(in   ) :: s(:)
    type(multifab) , intent(in   ) :: rho_Hnuc(:)
    type(multifab) , intent(in   ) :: rho_Hext(:)
    type(multifab) , intent(in   ) :: thermal(:)
    type(multifab) , intent(in   ) :: rho_omegadot(:)    
    type(multifab) , intent(in   ) :: u(:)
    type(multifab) , intent(in   ) :: normal(:)
    real(kind=dp_t), intent(in   ) ::      rho0(:,0:)
    real(kind=dp_t), intent(in   ) ::     rhoh0(:,0:)
    real(kind=dp_t), intent(in   ) ::        p0(:,0:)
    real(kind=dp_t), intent(in   ) ::   tempbar(:,0:)
    real(kind=dp_t), intent(in   ) :: gamma1bar(:,0:)
    real(kind=dp_t), intent(in   ) :: div_coeff(:,0:)
    real(kind=dp_t), intent(in   ) ::        w0(:,0:)
    type(ml_layout), intent(in   ) :: mla
    type(bc_tower) , intent(in   ) :: the_bc_tower


    ! Local
    real(kind=dp_t), pointer::  sp(:,:,:,:)
    real(kind=dp_t), pointer::  rhnp(:,:,:,:)
    real(kind=dp_t), pointer::  rhep(:,:,:,:)
    real(kind=dp_t), pointer::  up(:,:,:,:)
    logical,         pointer :: mp(:,:,:,:)


    real(kind=dp_t) :: T_max, T_max_level, T_max_local
    real(kind=dp_t) :: coord_T_max(mla%dim), coord_T_max_level(mla%dim), &
                       coord_T_max_local(mla%dim)

    real(kind=dp_t) :: enuc_max, enuc_max_level, enuc_max_local
    real(kind=dp_t) :: coord_enuc_max(mla%dim), coord_enuc_max_level(mla%dim), &
                       coord_enuc_max_local(mla%dim)

    real(kind=dp_t) :: total_c12_mass, total_c12_mass_level, &
                       total_c12_mass_local

    ! buffers
    real(kind=dp_t) :: T_max_data_local(1), T_max_coords_local(mla%dim)
    real(kind=dp_t), allocatable :: T_max_data(:), T_max_coords(:)

    real(kind=dp_t) :: enuc_max_data_local(1), enuc_max_coords_local(mla%dim)
    real(kind=dp_t), allocatable :: enuc_max_data(:), enuc_max_coords(:)

    real(kind=dp_t) :: sum_data_level(1), sum_data_local(1)

    integer :: lo(mla%dim),hi(mla%dim),ng_s,ng_u,ng_rhn,ng_rhe,dm,nlevs
    integer :: i,n, index_max
    integer :: un, un2
    logical :: lexist

    logical, save :: firstCall = .true.

    type(bl_prof_timer), save :: bpt

    call build(bpt, "diagnostics")

    dm = mla%dim
    nlevs = mla%nlevel

    ng_s = s(1)%ng
    ng_u = u(1)%ng
    ng_rhn = rho_Hnuc(1)%ng
    ng_rhe = rho_Hext(1)%ng

    ! initialize
    ! note that T_max corresponds to the maximum temperature in the 
    ! helium layer defined by X(He4) >= diag_define_he_layer
    T_max       = ZERO
    coord_T_max(:) = ZERO

    enuc_max    = ZERO
    coord_enuc_max(:) = ZERO

    total_c12_mass = ZERO

    ! loop over the levels and calculate global quantities
    do n = 1, nlevs

       ! initialize local and level quantities
       T_max_local     = ZERO
       T_max_level     = ZERO

       coord_T_max_level(:) = ZERO
       coord_T_max_local(:) = ZERO

       enuc_max_local     = ZERO
       enuc_max_level     = ZERO

       coord_enuc_max_level(:) = ZERO
       coord_enuc_max_local(:) = ZERO
       
       total_c12_mass_local = ZERO
       total_c12_mass_level = ZERO

       ! loop over the boxes at the current level
       do i = 1, nfabs(s(n))

          sp => dataptr(s(n) , i)
          rhnp => dataptr(rho_Hnuc(n), i)
          rhep => dataptr(rho_Hext(n), i)
          up => dataptr(u(n) , i)
          lo =  lwb(get_box(s(n), i))
          hi =  upb(get_box(s(n), i))

          ! build the local data
          select case (dm)
          case (2)
             ! only do those boxes that aren't masked
             if (n .eq. nlevs) then
                
                call diag_2d(n,time,dt,dx(n,:), &
                             sp(:,:,1,:),ng_s, &
                             rhnp(:,:,1,1),ng_rhn, &
                             rhep(:,:,1,1),ng_rhe, &
                             rho0(n,:),rhoh0(n,:), &
                             p0(n,:),tempbar(n,:),gamma1bar(n,:), &
                             up(:,:,1,:),ng_u, &
                             w0(n,:), &
                             lo,hi, &
                             T_max_local, &
                             coord_T_max_local, &
                             enuc_max_local, &
                             coord_enuc_max_local, &
                             total_c12_mass_local)
             else
                mp => dataptr(mla%mask(n),i)
                call diag_2d(n,time,dt,dx(n,:), &
                             sp(:,:,1,:),ng_s, &
                             rhnp(:,:,1,1),ng_rhn, &
                             rhep(:,:,1,1),ng_rhe, &
                             rho0(n,:),rhoh0(n,:), &
                             p0(n,:),tempbar(n,:),gamma1bar(n,:), &
                             up(:,:,1,:),ng_u, &
                             w0(n,:), &
                             lo,hi, &
                             T_max_local, &
                             coord_T_max_local, &
                             enuc_max_local, &
                             coord_enuc_max_local, &
                             total_c12_mass_local, &
                             mp(:,:,1,1))
             endif
          case (3)
             ! only do those boxes that aren't masked
             if (n .eq. nlevs) then

                call diag_3d(n,time,dt,dx(n,:), &
                             sp(:,:,:,:),ng_s, &
                             rhnp(:,:,:,1),ng_rhn, &
                             rhep(:,:,:,1),ng_rhe, &
                             rho0(n,:),rhoh0(n,:), &
                             p0(n,:),tempbar(n,:),gamma1bar(n,:), &
                             up(:,:,:,:),ng_u, &
                             w0(n,:), &
                             lo,hi, &
                             T_max_local, &
                             coord_T_max_local, &
                             enuc_max_local, &
                             coord_enuc_max_local, &
                             total_c12_mass_local)

             else
                mp => dataptr(mla%mask(n),i)
                call diag_3d(n,time,dt,dx(n,:), &
                             sp(:,:,:,:),ng_s, &
                             rhnp(:,:,:,1),ng_rhn, &
                             rhep(:,:,:,1),ng_rhe, &
                             rho0(n,:),rhoh0(n,:), &
                             p0(n,:),tempbar(n,:),gamma1bar(n,:), &
                             up(:,:,:,:),ng_u, &
                             w0(n,:), &
                             lo,hi, &
                             T_max_local, &
                             coord_T_max_local, &
                             enuc_max_local, &
                             coord_enuc_max_local, &
                             total_c12_mass_local, &
                             mp(:,:,:,1))
             endif
          end select
       end do

       ! build the level data
       
       ! get the maximum temperature and its location
       ! gather all the T_max data into an array; find the index of the maximum
       allocate(T_max_data(parallel_nprocs()))
       T_max_data_local(1) = T_max_local

       call parallel_gather(T_max_data_local, T_max_data, 1, &
                            root = parallel_IOProcessorNode())
       
       if (parallel_IOProcessor()) &
            index_max = maxloc(T_max_data, dim=1)

       ! gather all the T_max_coords into an array and use index_max to 
       ! get the correct location
       allocate(T_max_coords(dm*parallel_nprocs()))
       T_max_coords_local(:) = coord_T_max_local(:)

       call parallel_gather(T_max_coords_local , T_max_coords, dm, &
                            root = parallel_IOProcessorNode())

       if (parallel_IOProcessor()) then
          T_max_level = T_max_data(index_max)
       
          coord_T_max_level(1) = T_max_coords(dm*(index_max-1) + 1)
          coord_T_max_level(2) = T_max_coords(dm*(index_max-1) + 2)
          if (dm>2) &
               coord_T_max_level(3) = T_max_coords(dm*(index_max-1) + 3)
       endif

       deallocate(T_max_data, T_max_coords)

       ! get the maximum enuc and its location
       allocate(enuc_max_data(parallel_nprocs()))
       enuc_max_data_local(1) = enuc_max_local

       call parallel_gather(enuc_max_data_local, enuc_max_data, 1, &
                            root = parallel_IOProcessorNode())

       if (parallel_IOProcessor()) &
            index_max = maxloc(enuc_max_data, dim=1)

       allocate(enuc_max_coords(dm*parallel_nprocs()))
       enuc_max_coords_local(:) = coord_enuc_max_local(:)

       call parallel_gather(enuc_max_coords_local, enuc_max_coords, dm, &
                            root = parallel_IOProcessorNode())

       if (parallel_IOProcessor()) then
          enuc_max_level = enuc_max_data(index_max)

          coord_enuc_max_level(1) = enuc_max_coords(dm*(index_max-1) + 1)
          coord_enuc_max_level(2) = enuc_max_coords(dm*(index_max-1) + 2)
          if(dm>2) &
               coord_enuc_max_level(3) = enuc_max_coords(dm*(index_max-1) + 3)
       endif

       deallocate(enuc_max_data, enuc_max_coords)

       ! get the total c12 mass
       sum_data_local(1) = total_c12_mass_local

       call parallel_reduce(sum_data_level, sum_data_local, MPI_SUM, &
                            proc = parallel_IOProcessorNode())
       
       total_c12_mass_level = sum_data_level(1)

       ! reduce the current level's data with the global data
       if (parallel_IOProcessor()) then

          if (T_max_level > T_max) then
             T_max = T_max_level

             coord_T_max(:) = coord_T_max_level(:)

          endif

          if (enuc_max_level > enuc_max) then
             enuc_max = enuc_max_level

             coord_enuc_max(:) = coord_enuc_max_level(:)

          endif

          total_c12_mass = total_c12_mass + total_c12_mass_level

       endif

    end do

    ! normalize the mass
    ! we weight things in the loop over zones by the coarse level resolution
    total_c12_mass = total_c12_mass * dx(1,1) * dx(1,2)
    if (dm>2) total_c12_mass = total_c12_mass * dx(1,3)

1000 format(1x,10(g20.10,1x))
1001 format("#",10(a18,1x))

    if (parallel_IOProcessor()) then

       ! open the diagnostic files for output, taking care not to overwrite
       ! an existing file
       un = unit_new()
       inquire(file="xrb_temp_diag.out", exist=lexist)
       if (lexist) then
          open(unit=un, file="xrb_temp_diag.out", &
               status="old", position="append")
       else
          open(unit=un, file="xrb_temp_diag.out", status="new")
       endif

       un2 = unit_new()
       inquire(file="xrb_enuc_diag.out", exist=lexist)
       if (lexist) then
          open(unit=un2, file="xrb_enuc_diag.out", &
               status="old", position="append")
       else
          open(unit=un2, file="xrb_enuc_diag.out", status="new")
       endif

       ! print the headers
       if(firstCall) then
          if (dm > 2) then
             write(un , 1001) "time", "max{T}", "x_loc", "y_loc", "z_loc"
             write(un2, 1001) "time", "max{enuc}", "x_loc", "y_loc", "z_loc", &
                  "mass_c12"
          else
             write(un , 1001) "time", "max{T}", "x_loc", "y_loc"
             write(un2, 1001) "time", "max{enuc}", "x_loc", "y_loc", "mass_c12"
          endif

          firstCall = .false.
       endif

       ! print the data
       write(un,  1000) time, T_max, (coord_T_max(i), i=1,dm)
       write(un2, 1000) time, enuc_max, (coord_enuc_max(i), i=1,dm), &
            total_c12_mass

       close(un )
       close(un2)
    endif

    call destroy(bpt)

  end subroutine diag


  subroutine flush_diag()
    ! flush_diag is called immediately before checkpointing.  If an
    ! implementation of these diagnostic routines wants to buffer the
    ! data a write out a lot of timestep's worth of information all 
    ! at once, flush_diag() is the routine that should do the writing.

  end subroutine flush_diag


  subroutine diag_2d(n,time,dt,dx, &
                     s,ng_s, &
                     rho_Hnuc,ng_rhn, &
                     rho_Hext,ng_rhe, &
                     rho0,rhoh0,p0,tempbar,gamma1bar, &
                     u,ng_u, &
                     w0, &
                     lo,hi, &
                     T_max, &
                     coord_T_max, &
                     enuc_max, &
                     coord_enuc_max, &
                     c12_mass, &
                     mask)

    use variables, only: rho_comp, spec_comp, temp_comp, rhoh_comp
    use network, only: nspec
    use probin_module, only: diag_define_he_layer, prob_lo, base_cutoff_density
    use bl_constants_module, only: HALF, ONE, FOUR

    integer, intent(in) :: n, lo(:), hi(:), ng_s, ng_u, ng_rhn, ng_rhe
    real (kind=dp_t), intent(in   ) ::      s(lo(1)-ng_s:,lo(2)-ng_s:,:)
    real (kind=dp_t), intent(in   ) :: rho_Hnuc(lo(1)-ng_rhn:,lo(2)-ng_rhn:)
    real (kind=dp_t), intent(in   ) :: rho_Hext(lo(1)-ng_rhe:,lo(2)-ng_rhe:)
    real (kind=dp_t), intent(in   ) :: rho0(0:), rhoh0(0:), &
                                         p0(0:),tempbar(0:),gamma1bar(0:)
    real (kind=dp_t), intent(in   ) ::      u(lo(1)-ng_u:,lo(2)-ng_u:,:)
    real (kind=dp_t), intent(in   ) :: w0(0:)
    real (kind=dp_t), intent(in   ) :: time, dt, dx(:)
    real (kind=dp_t), intent(inout) :: T_max, enuc_max
    real (kind=dp_t), intent(inout) :: coord_T_max(2), coord_enuc_max(2)
    real (kind=dp_t), intent(inout) :: c12_mass
    logical,          intent(in   ), optional :: mask(lo(1):,lo(2):)

    !     Local variables
    integer                     :: i, j
    real (kind=dp_t) :: x, y 
    real (kind=dp_t) :: enuc_local
    logical :: cell_valid
    real (kind=dp_t) :: weight

    ! weight is the volume of a cell at the current level divided by the
    ! volume of a cell at the COARSEST level
    weight = ONE / FOUR**(n-1)

    do j = lo(2), hi(2)
       y = prob_lo(2) + (dble(j) + HALF) * dx(2)

       do i = lo(1), hi(1)
          x = prob_lo(1) + (dble(i) + HALF) * dx(1)

          cell_valid = .true.
          if (present(mask)) then
             if ( (.not. mask(i,j)) ) cell_valid = .false.
          endif

          if (cell_valid .and. s(i,j,rho_comp) > base_cutoff_density) then

             ! temperature diagnostic
             ! check to see if we are in the helium layer
             ! if we are, then get T_max and its loc
             if ( s(i,j,spec_comp) .ge. &
		  diag_define_he_layer * s(i,j,rho_comp) ) then

                if (s(i,j,temp_comp) > T_max) then
                
                   T_max = s(i,j,temp_comp)
                
                   coord_T_max(1) = x
                   coord_T_max(2) = y

                endif
             endif

             ! enuc diagnostic
             enuc_local = rho_Hnuc(i,j)/s(i,j,rho_comp)
             if (enuc_local > enuc_max) then

                enuc_max = enuc_local
             
                coord_enuc_max(1) = x
                coord_enuc_max(2) = y

             endif

             ! c12 mass diagnostic
             c12_mass = c12_mass + weight*s(i,j,spec_comp+1)

          endif

       enddo
    enddo

  end subroutine diag_2d

  subroutine diag_3d(n,time,dt,dx, &
                     s,ng_s, &
                     rho_Hnuc,ng_rhn, &
                     rho_Hext,ng_rhe, &
                     rho0,rhoh0,p0,tempbar,gamma1bar, &
                     u,ng_u,w0, &
                     lo,hi, &
                     T_max, &
                     coord_T_max, &
                     enuc_max, &
                     coord_enuc_max, &
                     c12_mass, &
                     mask)

    use variables, only: rho_comp, spec_comp, temp_comp, rhoh_comp
    use network, only: nspec
    use bl_constants_module, only: HALF, ONE, EIGHT
    use probin_module, only: diag_define_he_layer, prob_lo, base_cutoff_density

    integer, intent(in) :: n,lo(:), hi(:), ng_s, ng_u, ng_rhn, ng_rhe
    real (kind=dp_t), intent(in   ) ::      s(lo(1)-ng_s:,lo(2)-ng_s:,lo(3)-ng_s:,:)
    real (kind=dp_t), intent(in   ) :: rho_Hnuc(lo(1)-ng_rhn:,lo(2)-ng_rhn:,lo(3)-ng_rhn:)
    real (kind=dp_t), intent(in   ) :: rho_Hext(lo(1)-ng_rhe:,lo(2)-ng_rhe:,lo(3)-ng_rhe:)
    real (kind=dp_t), intent(in   ) :: rho0(0:), rhoh0(0:), &
                                         p0(0:),tempbar(0:),gamma1bar(0:)
    real (kind=dp_t), intent(in   ) ::      u(lo(1)-ng_u:,lo(2)-ng_u:,lo(3)-ng_u:,:)
    real (kind=dp_t), intent(in   ) :: w0(0:)
    real (kind=dp_t), intent(in   ) :: time, dt, dx(:)
    real (kind=dp_t), intent(inout) :: T_max, enuc_max
    real (kind=dp_t), intent(inout) :: coord_T_max(3), coord_enuc_max(3)
    real (kind=dp_t), intent(inout) :: c12_mass
    logical,          intent(in   ), optional :: mask(lo(1):,lo(2):,lo(3):)

    !     Local variables
    integer                     :: i, j, k
    real (kind=dp_t) :: x, y , z
    real (kind=dp_t) :: enuc_local
    logical :: cell_valid
    real (kind=dp_t) :: weight


    ! weight is the volume of a cell at the current level divided by the
    ! volume of a cell at the COARSEST level
    weight = ONE / EIGHT**(n-1)

    do k = lo(3), hi(3)
       z = prob_lo(3) + (dble(k) + HALF) * dx(3)       
       do j = lo(2), hi(2)
          y = prob_lo(2) + (dble(j) + HALF) * dx(2)
          do i = lo(1), hi(1)
             x = prob_lo(1) + (dble(i) + HALF) * dx(1)

             cell_valid = .true.
             if (present(mask)) then
                if ( (.not. mask(i,j,k)) ) cell_valid = .false.
             endif

             if (cell_valid .and. s(i,j,k,rho_comp) > base_cutoff_density) then

                ! temperature diagnostic
                ! check to see if we are in the helium layer
                ! if we are, then get T_max
                if ( s(i,j,k,spec_comp) .ge. &
                     diag_define_he_layer * s(i,j,k,rho_comp) ) then

                   if (s(i,j,k,temp_comp) > T_max) then
                   
                      T_max = s(i,j,k,temp_comp)

                      coord_T_max(1) = x
                      coord_T_max(2) = y
                      coord_T_max(3) = z
                   
                   endif
                endif

                ! enuc diagnostic
                enuc_local = rho_Hnuc(i,j,k)/s(i,j,k,rho_comp)
                if (enuc_local > enuc_max) then
                
                   enuc_max = enuc_local

                   coord_enuc_max(1) = x
                   coord_enuc_max(2) = y
                   coord_enuc_max(3) = z

                endif

                ! c12 mass diagnostic
                c12_mass = c12_mass + weight*s(i,j,k,spec_comp+1)

             endif

          enddo
       enddo
    enddo

  end subroutine diag_3d

end module diag_module