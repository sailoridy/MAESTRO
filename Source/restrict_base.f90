module restrict_base_module

  use bl_types

  implicit none

  private

  public :: restrict_base

contains

  subroutine restrict_base(nlevs,s0,is_cell_centered)

    use bl_prof_module
    use geometry, only: r_start_coord, r_end_coord

    integer        , intent(in   ) :: nlevs
    real(kind=dp_t), intent(inout) :: s0(:,0:)
    logical        , intent(in   ) :: is_cell_centered

    ! local
    integer :: n, r

    type(bl_prof_timer), save :: bpt

    call build(bpt, "restrict_base")

    if (is_cell_centered) then

       do n=nlevs,2,-1
          ! for level n, make the coarser cells underneath simply the average of the fine
          do r=r_start_coord(n),r_end_coord(n)-1,2
             s0(n-1,r/2) = 0.5d0 * (s0(n,r) + s0(n,r+1))
          end do
       end do

    else

       do n=nlevs,2,-1
          ! for level n, make the coarse edge underneath equal to the fine edge value
          do r=r_start_coord(n),r_end_coord(n)+1,2
             s0(n-1,r/2) = s0(n,r)
          end do
       end do

    end if

    call destroy(bpt)

  end subroutine restrict_base

end module restrict_base_module
